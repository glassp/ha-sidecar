"""Runtime representation of one connected tablet."""

from __future__ import annotations

import asyncio
import logging
from typing import Any

from aiohttp import web

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.core import Event, EventStateChangedData
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_track_state_change_event

from .const import (
    COMMAND_TIMEOUT,
    CONF_DEVICE_ID,
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
        self.state: dict[str, Any] = {}
        self.info: dict[str, Any] = {}
        self._ws: web.WebSocketResponse | None = None
        self._pending: dict[int, asyncio.Future[dict[str, Any]]] = {}
        self._next_id = 1

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
        self.state.update(partial)
        self._notify()

    @callback
    def handle_event(self, event: str, data: dict[str, Any]) -> None:
        self.hass.bus.async_fire(
            EVENT_SIDECAR, {"device_id": self.device_id, "name": self.name, "event": event, **data}
        )

    @callback
    def handle_result(self, msg: dict[str, Any]) -> None:
        fut = self._pending.pop(msg.get("id"), None)
        if fut is not None and not fut.done():
            fut.set_result(msg)

    # --- outbound ---------------------------------------------------------------------------

    async def send_command(self, command: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
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
            async with asyncio.timeout(COMMAND_TIMEOUT):
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

    @callback
    def async_start_input_tracking(self) -> None:
        """Forward the chosen presence / night entities to the tablet whenever they change."""
        entities = [*self._presence_entities, *([self._night_entity] if self._night_entity else [])]
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
        except HomeAssistantError as err:
            _LOGGER.debug("Could not sync inputs to %s: %s", self.name, err)
