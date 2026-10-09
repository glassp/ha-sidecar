"""Runtime representation of one connected tablet."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from aiohttp import web

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.core import Event, EventStateChangedData
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_track_state_change_event, async_track_time_interval
from homeassistant.util import dt as dt_util, slugify

from .beacon import BeaconState, BeaconTracker
from .const import (
    CONF_BEACON_HEAL,
    CONF_BEACON_TIMEOUT,
    COMMAND_TIMEOUT,
    CONF_DEVICE_ID,
    CONF_ENTITY_PREFIX,
    CONF_GLANCE_ENTITIES,
    CONF_NIGHT_ENTITY,
    CONF_PRESENCE_ENTITIES,
    CONF_TOKEN,
    EVENT_SIDECAR,
)

_LOGGER = logging.getLogger(__name__)


class SidecarDevice:
    """One paired tablet. Owns the live WebSocket and the last known state."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self.device_id: str = entry.data[CONF_DEVICE_ID]
        self.token: str = entry.data[CONF_TOKEN]
        self.name: str = entry.title
        # entries created before the prefix existed fall back to the slug of their name
        self.entity_prefix: str = entry.data.get(CONF_ENTITY_PREFIX) or slugify(entry.title)
        self.state: dict[str, Any] = {}
        self.info: dict[str, Any] = {}
        self._ws: web.WebSocketResponse | None = None
        self._pending: dict[int, asyncio.Future[dict[str, Any]]] = {}
        self._next_id = 1
        self.beacon = BeaconTracker(timedelta(minutes=self.beacon_timeout_minutes))
        self.beacon_state = BeaconState.PAUSED
        self._beacon_episode = False
        self._started_at = dt_util.utcnow()
        # set by the Assist satellite entity while it exists: receives the tablet's `voice` messages
        self.voice_handler: Callable[[dict[str, Any]], None] | None = None

    @property
    def beacon_timeout_minutes(self) -> int:
        return int(self.entry.options.get(CONF_BEACON_TIMEOUT) or 4)

    @property
    def beacon_heal_enabled(self) -> bool:
        return bool(self.entry.options.get(CONF_BEACON_HEAL))

    @property
    def last_beacon(self) -> datetime | None:
        return self.beacon.last

    @property
    def signal(self) -> str:
        """Dispatcher signal fired on any state/availability change."""
        return f"ha_sidecar_update_{self.device_id}"

    @property
    def connected(self) -> bool:
        return self._ws is not None and not self._ws.closed

    @callback
    def _notify(self) -> None:
        async_dispatcher_send(self.hass, self.signal)

    # --- connection lifecycle (called by the WebSocket view) ---------------------------------

    @callback
    def attach(self, ws: web.WebSocketResponse, info: dict[str, Any]) -> None:
        """Adopt a freshly authenticated socket, dropping any stale one."""
        old, self._ws = self._ws, ws
        if old is not None and not old.closed:
            self.hass.async_create_task(old.close())
        self.info = info
        self._notify()

    @callback
    def detach(self, ws: web.WebSocketResponse) -> None:
        if self._ws is not ws:
            return  # already replaced by a newer connection
        self._ws = None
        for fut in self._pending.values():
            if not fut.done():
                fut.set_exception(HomeAssistantError("Tablet disconnected"))
        self._pending.clear()
        self._notify()

    # --- inbound ----------------------------------------------------------------------------

    @callback
    def update_state(self, partial: dict[str, Any]) -> None:
        was_front = self._companion_in_front()
        self.state.update(partial)
        if not was_front and self._companion_in_front():
            self.beacon.disarm()  # a fresh page: wait for its first beacon before judging it
        self._notify()

    @callback
    def handle_event(self, event: str, data: dict[str, Any]) -> None:
        if event == "companion_restarted":
            self.beacon.disarm()
        self.hass.bus.async_fire(
            EVENT_SIDECAR, {"device_id": self.device_id, "name": self.name, "event": event, **data}
        )

    @callback
    def handle_voice(self, msg: dict[str, Any]) -> None:
        if self.voice_handler is not None:
            self.voice_handler(msg)

    @callback
    def handle_result(self, msg: dict[str, Any]) -> None:
        fut = self._pending.pop(msg.get("id"), None)
        if fut is not None and not fut.done():
            fut.set_result(msg)

    # --- outbound ---------------------------------------------------------------------------

    @callback
    def push(self, msg: dict[str, Any]) -> None:
        """Send a message that needs no answer (voice events); dropped while the tablet is away."""
        ws = self._ws
        if ws is not None and not ws.closed:
            self.hass.async_create_task(ws.send_json(msg))

    async def send_command(
        self, command: str, data: dict[str, Any] | None = None, timeout: float = COMMAND_TIMEOUT
    ) -> dict[str, Any]:
        """Send a command and wait for the tablet's result; raises on failure."""
        if not self.connected:
            raise HomeAssistantError(f"{self.name} is not connected")
        cmd_id = self._next_id
        self._next_id += 1
        fut: asyncio.Future[dict[str, Any]] = self.hass.loop.create_future()
        self._pending[cmd_id] = fut
        assert self._ws is not None
        await self._ws.send_json({"type": "command", "id": cmd_id, "command": command, "data": data or {}})
        try:
            async with asyncio.timeout(timeout):
                msg = await fut
        except TimeoutError as err:
            self._pending.pop(cmd_id, None)
            raise HomeAssistantError(f"{self.name} did not answer '{command}' in time") from err
        if not msg.get("success"):
            error, detail = msg.get("error"), msg.get("message")
            suffix = f" ({detail})" if detail and detail != error else ""
            raise HomeAssistantError(f"{command} failed on {self.name}: {error}{suffix}")
        return msg.get("data") or {}

    # --- HA entities that drive the tablet (presence, night) ---------------------------------

    @property
    def _presence_entities(self) -> list[str]:
        return list(self.entry.options.get(CONF_PRESENCE_ENTITIES) or [])

    @property
    def _night_entity(self) -> str | None:
        return self.entry.options.get(CONF_NIGHT_ENTITY) or None

    @property
    def _glance_entities(self) -> list[str]:
        return list(self.entry.options.get(CONF_GLANCE_ENTITIES) or [])[:9]

    @callback
    def async_start_input_tracking(self) -> None:
        """Forward the chosen presence / night entities to the tablet whenever they change."""
        entities = [
            *self._presence_entities,
            *([self._night_entity] if self._night_entity else []),
            *self._glance_entities,
        ]
        if not entities:
            return

        @callback
        def _changed(event: Event[EventStateChangedData]) -> None:
            if self.connected:
                self.hass.async_create_task(self.async_sync_inputs())

        self.entry.async_on_unload(async_track_state_change_event(self.hass, entities, _changed))

    async def async_sync_inputs(self) -> None:
        """Push current presence / night state (also called right after the tablet connects)."""
        try:
            if self._presence_entities:
                present = any(self.hass.states.is_state(e, "on") for e in self._presence_entities)
                await self.send_command("external_presence", {"present": present})
            if self._night_entity:
                state = self.hass.states.get(self._night_entity)
                night: bool | None
                if state is None or state.state in ("unavailable", "unknown"):
                    night = None
                elif state.domain == "sun":
                    night = state.state == "below_horizon"
                else:
                    night = state.state == "on"
                await self.send_command("external_night", {"night": night})
            if self._glance_entities:
                await self.send_command("glance_items", {"items": self._glance_items()})
        except HomeAssistantError as err:
            _LOGGER.debug("Could not sync inputs to %s: %s", self.name, err)

    def _glance_items(self) -> list[dict[str, str]]:
        items = []
        for entity_id in self._glance_entities:
            state = self.hass.states.get(entity_id)
            if state is None:
                continue
            unit = state.attributes.get("unit_of_measurement")
            value = state.state if state.state not in ("unknown", "unavailable") else "–"
            if value != "–" and state.attributes.get("device_class") == "timestamp":
                parsed = dt_util.parse_datetime(value)
                if parsed is not None:
                    value = dt_util.as_local(parsed).strftime("%H:%M")
            name = str(state.attributes.get("friendly_name") or entity_id)
            if name.startswith(f"{self.name} "):  # "Kitchen tablet Temperature" -> "Temperature"
                name = name[len(self.name) + 1 :]
            items.append({"name": str(name), "value": f"{value} {unit}" if unit and value != "–" else value})
        return items


    # --- dashboard beacon ----------------------------------------------------------------------------

    def _companion_in_front(self) -> bool:
        return self.state.get("foreground_app") in (self.state.get("companion_packages") or [])

    def _beacon_watching(self) -> bool:
        """Pings are expected only while the screen is on, the companion app is in front and everything is up."""
        return (
            self.connected
            and self.state.get("screen_on") is True
            and self._companion_in_front()
            and dt_util.utcnow() - self._started_at > timedelta(minutes=2)  # Home Assistant just started: dashboards reconnect
        )

    @callback
    def handle_beacon(self, active: bool = True, reason: str | None = None, path: str | None = None) -> None:
        self.beacon.timeout = timedelta(minutes=self.beacon_timeout_minutes)
        if active:
            if self._beacon_episode:
                self.hass.bus.async_fire(
                    EVENT_SIDECAR, {"device_id": self.device_id, "name": self.name, "event": "dashboard_recovered", "path": path}
                )
            self.beacon.record(dt_util.utcnow(), path)
            self._beacon_episode = False
        else:
            self.beacon.mark_inactive(reason, path)
            self._beacon_episode = False
        self._set_beacon_state(self.beacon.evaluate(dt_util.utcnow(), watching=self._beacon_watching()))

    @callback
    def _set_beacon_state(self, state: BeaconState) -> None:
        if state != self.beacon_state:
            self.beacon_state = state
            self._notify()

    @callback
    def async_start_beacon_monitor(self) -> None:
        @callback
        def _tick(_now: datetime) -> None:
            self.hass.async_create_task(self._async_beacon_tick())

        self.entry.async_on_unload(async_track_time_interval(self.hass, _tick, timedelta(seconds=30)))

    async def _async_beacon_tick(self) -> None:
        now = dt_util.utcnow()
        self.beacon.timeout = timedelta(minutes=self.beacon_timeout_minutes)
        state = self.beacon.evaluate(now, watching=self._beacon_watching())
        self._set_beacon_state(state)
        if state != BeaconState.STALE:
            return
        if not self._beacon_episode:  # once per episode; the remedies below are retried on later ticks
            self._beacon_episode = True
            self.hass.bus.async_fire(
                EVENT_SIDECAR,
                {"device_id": self.device_id, "name": self.name, "event": "dashboard_unresponsive",
                 "last_beacon": self.beacon.last.isoformat() if self.beacon.last else None},
            )
        if not self.beacon_heal_enabled:
            return
        # a silent beacon is only a suspicion (wrong page, dropped connection, hung page): gentlest remedy first
        kiosk_path = ((self.state.get("cfg") or {}).get("kiosk_dashboard") or "").strip()
        action = self.beacon.next_action(now, can_navigate=bool(kiosk_path))
        try:
            if action == "navigate":
                await self.send_command("bring_to_front", {"path": kiosk_path})
                self.hass.bus.async_fire(
                    EVENT_SIDECAR,
                    {"device_id": self.device_id, "name": self.name, "event": "dashboard_navigate_attempt", "path": kiosk_path},
                )
            elif action == "heal":
                result = await self.send_command("heal_dashboard", {"reason": "beacon"})
                self.beacon.healed(now)
                _LOGGER.info("Dashboard beacon of %s stayed silent: heal %s", self.name, result)
        except HomeAssistantError as err:
            _LOGGER.warning("Could not recover the dashboard on %s: %s", self.name, err)
