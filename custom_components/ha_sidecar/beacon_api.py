"""WebSocket commands used by the dashboard beacon card."""

from __future__ import annotations

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback

from .const import DOMAIN
from .device import SidecarDevice


def _by_prefix(hass: HomeAssistant, prefix: str) -> SidecarDevice | None:
    for device in hass.data.get(DOMAIN, {}).get("devices", {}).values():
        if device.entity_prefix == prefix:
            return device
    return None


@callback
def async_register(hass: HomeAssistant) -> None:
    websocket_api.async_register_command(hass, ws_beacon)
    websocket_api.async_register_command(hass, ws_tablets)


@websocket_api.websocket_command({vol.Required("type"): "ha_sidecar/beacon", vol.Required("tablet"): str})
@callback
def ws_beacon(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    """A ping from the card. Answering proves the whole round trip (page -> Home Assistant -> page) works."""
    device = _by_prefix(hass, msg["tablet"])
    if device is None:
        connection.send_error(msg["id"], "unknown_tablet", f"No tablet with the prefix '{msg['tablet']}'")
        return
    device.handle_beacon()
    connection.send_result(msg["id"], {"ok": True, "state": str(device.beacon_state), "timeout_s": int(device.beacon.timeout.total_seconds())})


@websocket_api.websocket_command({vol.Required("type"): "ha_sidecar/tablets"})
@callback
def ws_tablets(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict) -> None:
    """The registered tablets, for the card's picker."""
    devices = hass.data.get(DOMAIN, {}).get("devices", {}).values()
    connection.send_result(
        msg["id"],
        [{"prefix": d.entity_prefix, "name": d.name, "device_id": d.device_id} for d in sorted(devices, key=lambda d: d.name)],
    )
