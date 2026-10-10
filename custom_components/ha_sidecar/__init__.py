"""HA Sidecar: kiosk lockdown, alarms and OS update control for Android tablets."""

from __future__ import annotations

import voluptuous as vol

from datetime import timedelta
import uuid

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv, device_registry as dr
from homeassistant.helpers.typing import ConfigType
from homeassistant.util import dt as dt_util, slugify

from .const import DOMAIN, VERSION
from . import beacon_api
from .device import SidecarDevice
from .frontend import async_register_card
from .websocket_view import SidecarWebSocketView

PLATFORMS = [
    Platform.ASSIST_SATELLITE,
    Platform.BINARY_SENSOR,
    Platform.BUTTON,
    Platform.MEDIA_PLAYER,
    Platform.NUMBER,
    Platform.SELECT,
    Platform.SENSOR,
    Platform.SWITCH,
    Platform.TEXT,
    Platform.TIME,
    Platform.UPDATE,
]

CONFIG_SCHEMA = cv.config_entry_only_config_schema(DOMAIN)

WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

_TARGET = {vol.Required("device_id"): vol.All(cv.ensure_list, [cv.string])}

# existing timers are addressed by id, or by the label they were started with (the id defaults to its slug)
def _timer_schema(extra: dict | None = None) -> vol.Schema:
    return vol.All(
        vol.Schema({**_TARGET, vol.Optional("timer_id"): cv.string, vol.Optional("label"): cv.string, **(extra or {})}),
        cv.has_at_least_one_key("timer_id", "label"),
    )


SERVICES: dict[str, vol.Schema] = {
    "launch_app": vol.Schema({**_TARGET, vol.Required("package"): cv.string, vol.Optional("path"): cv.string}),
    "bring_to_front": vol.Schema({**_TARGET, vol.Optional("path"): cv.string}),
    "set_allowlist": vol.Schema({**_TARGET, vol.Required("packages"): vol.All(cv.ensure_list, [cv.string])}),
    "set_alarm": vol.Schema(
        {
            **_TARGET,
            vol.Optional("alarm_id"): cv.string,
            vol.Required("time"): cv.time,
            vol.Optional("days", default=[]): vol.All(cv.ensure_list, [vol.In(WEEKDAYS)]),
            vol.Optional("label", default=""): cv.string,
            vol.Optional("enabled", default=True): cv.boolean,
            vol.Optional("snooze_minutes", default=9): vol.All(vol.Coerce(int), vol.Range(min=1, max=60)),
        }
    ),
    "cancel_alarm": vol.Schema({**_TARGET, vol.Required("alarm_id"): cv.string}),
    "stop_alarm": vol.Schema(_TARGET),
    "restart_companion": vol.Schema(_TARGET),
    "listen": vol.Schema(_TARGET),
    "cancel_listening": vol.Schema(_TARGET),
    "snooze_alarm": vol.Schema(_TARGET),
    "enter_night_mode": vol.Schema(_TARGET),
    "exit_night_mode": vol.Schema({**_TARGET, vol.Optional("follow_schedule", default=False): cv.boolean}),
    "set_alarm_enabled": vol.Schema({**_TARGET, vol.Required("alarm_id"): cv.string, vol.Required("enabled"): cv.boolean}),
    "skip_next_alarm": vol.Schema({**_TARGET, vol.Optional("alarm_id"): cv.string}),
    "mute_alarms": vol.Schema({**_TARGET, vol.Optional("duration"): cv.time_period}),
    "unmute_alarms": vol.Schema(_TARGET),
    "start_timer": vol.Schema(
        {
            **_TARGET,
            vol.Required("duration"): vol.All(cv.time_period, vol.Range(min=timedelta(seconds=1), max=timedelta(hours=99))),
            vol.Optional("label", default=""): cv.string,
            vol.Optional("timer_id"): cv.string,
        }
    ),
    "start_stopwatch": vol.Schema({**_TARGET, vol.Optional("label", default=""): cv.string, vol.Optional("timer_id"): cv.string}),
    "pause_timer": _timer_schema(),
    "resume_timer": _timer_schema(),
    "cancel_timer": _timer_schema(),
    "adjust_timer": _timer_schema({vol.Required("seconds"): vol.All(vol.Coerce(int), vol.Range(min=-86400, max=86400))}),
    "install_system_update": vol.Schema({**_TARGET, vol.Required("uri"): cv.string}),
}


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    hass.data.setdefault(DOMAIN, {"devices": {}})
    hass.http.register_view(SidecarWebSocketView())
    beacon_api.async_register(hass)
    await async_register_card(hass, VERSION)

    async def handle_service(call: ServiceCall) -> None:
        for device in _resolve_devices(hass, call.data["device_id"]):
            command, data = _build_command(call.service, call.data)
            await device.send_command(command, data)

    for name, schema in SERVICES.items():
        hass.services.async_register(DOMAIN, name, handle_service, schema=schema)
    return True


def _resolve_devices(hass: HomeAssistant, ha_device_ids: list[str]) -> list[SidecarDevice]:
    registry = dr.async_get(hass)
    devices: list[SidecarDevice] = []
    for ha_id in ha_device_ids:
        entry = registry.async_get(ha_id)
        if entry is None:
            continue
        for domain, ident in entry.identifiers:
            if domain == DOMAIN and ident in hass.data[DOMAIN]["devices"]:
                devices.append(hass.data[DOMAIN]["devices"][ident])
    if not devices:
        raise ServiceValidationError("No HA Sidecar device targeted")
    return devices


def _build_command(service: str, data: dict) -> tuple[str, dict]:
    if service == "listen":
        return "voice_listen", {}
    if service == "cancel_listening":
        return "voice_cancel", {}
    if service == "launch_app":
        return "launch_app", {"package": data["package"], "path": data.get("path")}
    if service == "bring_to_front":
        return "bring_to_front", {"path": data.get("path")}
    if service == "set_allowlist":
        return "set_allowlist", {"packages": data["packages"]}
    if service == "set_alarm":
        t = data["time"]
        return "set_alarm", {
            "alarm": {
                "id": data.get("alarm_id") or f"ha-{t.hour:02d}{t.minute:02d}-{'-'.join(data['days']) or 'once'}",
                "hour": t.hour,
                "minute": t.minute,
                "days": [WEEKDAYS.index(d) + 1 for d in data["days"]],
                "label": data["label"],
                "enabled": data["enabled"],
                "snooze_minutes": data["snooze_minutes"],
            }
        }
    if service == "cancel_alarm":
        return "cancel_alarm", {"id": data["alarm_id"]}
    if service == "install_system_update":
        return "install_system_update", {"uri": data["uri"]}
    if service == "enter_night_mode":
        return "external_night", {"night": True}
    if service == "exit_night_mode":
        # False forces day until changed again; follow_schedule hands control back to the night start/end times
        return "external_night", {"night": None if data["follow_schedule"] else False}
    if service == "set_alarm_enabled":
        return "set_alarm_enabled", {"id": data["alarm_id"], "enabled": data["enabled"]}
    if service == "skip_next_alarm":
        return "skip_next_alarm", {"id": data.get("alarm_id")}
    if service == "mute_alarms":
        if (duration := data.get("duration")) is None:
            return "mute_alarms", {}  # until unmuted
        return "mute_alarms", {"until_ms": int((dt_util.utcnow() + duration).timestamp() * 1000)}
    if service == "start_timer":
        return "start_timer", {
            "id": _timer_id(data),
            "label": data["label"],
            "kind": "countdown",
            "duration_s": int(data["duration"].total_seconds()),
        }
    if service == "start_stopwatch":
        return "start_timer", {"id": _timer_id(data), "label": data["label"], "kind": "countup"}
    if service in ("pause_timer", "resume_timer", "cancel_timer"):
        return service, {"id": _timer_id(data, create=False)}
    if service == "adjust_timer":
        return "adjust_timer", {"id": _timer_id(data, create=False), "delta_s": data["seconds"]}
    return service, {}  # stop_alarm, snooze_alarm, unmute_alarms


def _timer_id(data: dict, *, create: bool = True) -> str:
    """`timer_id`, else the slug of the label (so `label: Batch 1` can start and later cancel the same timer)."""
    if data.get("timer_id"):
        return data["timer_id"]
    if data.get("label") and (slug := slugify(data["label"])):
        return slug
    if create:
        return f"ha-{uuid.uuid4().hex[:8]}"
    raise ServiceValidationError("Give timer_id or label")


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    device = SidecarDevice(hass, entry)
    hass.data[DOMAIN]["devices"][device.device_id] = device
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    device.async_start_input_tracking()
    device.async_start_beacon_monitor()
    entry.async_on_unload(entry.add_update_listener(_async_options_updated))
    return True


async def _async_options_updated(hass: HomeAssistant, entry: ConfigEntry) -> None:
    await hass.config_entries.async_reload(entry.entry_id)


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    if unloaded := await hass.config_entries.async_unload_platforms(entry, PLATFORMS):
        device = hass.data[DOMAIN]["devices"].pop(entry.data["device_id"], None)
        if device is not None and device.connected:
            await device._ws.close()  # noqa: SLF001 - tablet reconnects and gets auth_failed
    return unloaded
