"""WebSocket endpoint the tablet connects to (docs/PROTOCOL.md)."""

from __future__ import annotations

import asyncio
import hmac
import logging
from typing import Any

from aiohttp import WSMsgType, web

from homeassistant.components.http import HomeAssistantView
from homeassistant.core import HomeAssistant
from homeassistant.helpers.http import KEY_HASS

from .const import DOMAIN, PROTOCOL_VERSION, WS_PATH
from .device import SidecarDevice

_LOGGER = logging.getLogger(__name__)
HELLO_TIMEOUT = 10


def _find_device(hass: HomeAssistant, token: Any) -> SidecarDevice | None:
    if not isinstance(token, str):
        return None
    match = None
    for device in hass.data[DOMAIN]["devices"].values():
        # compare against every device so timing does not reveal which token prefix matched
        if hmac.compare_digest(device.token.encode(), token.encode()):
            match = device
    return match


class SidecarWebSocketView(HomeAssistantView):
    """Unauthenticated at the HTTP layer; authenticates with the per-device token in `hello`."""

    url = WS_PATH
    name = "api:ha_sidecar:ws"
    requires_auth = False

    async def get(self, request: web.Request) -> web.WebSocketResponse:
        hass: HomeAssistant = request.app[KEY_HASS]
        ws = web.WebSocketResponse(heartbeat=30)
        await ws.prepare(request)

        device: SidecarDevice | None = None
        try:
            hello = await ws.receive_json(timeout=HELLO_TIMEOUT)
            if hello.get("type") != "hello" or hello.get("protocol") != PROTOCOL_VERSION:
                await ws.send_json({"type": "error", "error": "unsupported_protocol"})
                await ws.close()
                return ws

            device = _find_device(hass, hello.get("token"))
            if device is None:
                _LOGGER.warning("Rejected tablet connection from %s: bad token", request.remote)
                await ws.send_json({"type": "auth_failed"})
                await ws.close()
                return ws

            device.attach(ws, hello.get("device") or {})
            await ws.send_json({"type": "hello_ok", "device_id": device.device_id, "protocol": PROTOCOL_VERSION})
            hass.async_create_task(device.async_sync_inputs())

            async for raw in ws:
                if raw.type != WSMsgType.TEXT:
                    if raw.type == WSMsgType.ERROR:
                        break
                    continue
                try:
                    msg = raw.json()
                except ValueError:
                    continue
                self._dispatch(device, msg)
        except (asyncio.TimeoutError, TypeError, ValueError):
            pass
        finally:
            if device is not None:
                device.detach(ws)
        return ws

    @staticmethod
    def _dispatch(device: SidecarDevice, msg: dict[str, Any]) -> None:
        kind = msg.get("type")
        if kind == "state" and isinstance(msg.get("state"), dict):
            device.update_state(msg["state"])
        elif kind == "event" and isinstance(msg.get("event"), str):
            device.handle_event(msg["event"], msg.get("data") or {})
        elif kind == "voice":
            device.handle_voice(msg)
        elif kind == "result":
            device.handle_result(msg)
