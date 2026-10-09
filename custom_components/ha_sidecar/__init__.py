"""HA Sidecar: kiosk lockdown, alarms and OS update control for Android tablets."""

from __future__ import annotations

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv, device_registry as dr
from homeassistant.helpers.typing import ConfigType

from .const import DOMAIN
from .device import SidecarDevice
from .websocket_view import SidecarWebSocketView

PLATFORMS = [
    Platform.BINARY_SENSOR,
    Platform.BUTTON,
    Platform.NUMBER,
    Platform.SENSOR,
    Platform.SWITCH,
    Platform.UPDATE,
]

CONFIG_SCHEMA = cv.config_entry_only_config_schema(DOMAIN)

WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

_TARGET = {vol.Required("device_id"): vol.All(cv.ensure_list, [cv.string])}

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
    "snooze_alarm": vol.Schema(_TARGET),
    "install_system_update": vol.Schema({**_TARGET, vol.Required("uri"): cv.string}),
}


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    hass.data.setdefault(DOMAIN, {"devices": {}})
    hass.http.register_view(SidecarWebSocketView())

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
    return service, {}  # stop_alarm, snooze_alarm


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    device = SidecarDevice(hass, entry)
    hass.data[DOMAIN]["devices"][device.device_id] = device
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    if unloaded := await hass.config_entries.async_unload_platforms(entry, PLATFORMS):
        device = hass.data[DOMAIN]["devices"].pop(entry.data["device_id"], None)
        if device is not None and device.connected:
            await device._ws.close()  # noqa: SLF001 - tablet reconnects and gets auth_failed
    return unloaded
