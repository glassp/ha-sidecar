"""Tests for SidecarDevice, the websocket view and the satellite's timer twins.

They need the Home Assistant package (the lab venv has it): `python -m pytest tests` or `python -m unittest discover -s tests`.
Skipped when it is not installed.
"""

import asyncio
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from custom_components.ha_sidecar.const import CONF_DEVICE_ID, CONF_TOKEN, EVENT_SIDECAR
    from custom_components.ha_sidecar.device import SidecarDevice
    from homeassistant.exceptions import HomeAssistantError

    HAVE_HA = True
except ImportError:  # pragma: no cover
    HAVE_HA = False


def make_device(loop=None):
    hass = MagicMock()
    hass.loop = loop
    entry = MagicMock()
    entry.data = {CONF_DEVICE_ID: "tab-1", CONF_TOKEN: "secret"}
    entry.title = "Kitchen tablet"
    entry.options = {}
    return hass, SidecarDevice(hass, entry)


def open_socket():
    ws = MagicMock()
    ws.closed = False
    ws.send_json = AsyncMock()
    ws.close = AsyncMock()
    return ws


@unittest.skipUnless(HAVE_HA, "needs the homeassistant package")
class EventTest(unittest.TestCase):
    def test_what_the_tablet_reports_cannot_replace_who_and_what(self):
        hass, device = make_device()
        device.handle_event("alarm_ringing", {"device_id": "someone-else", "event": "lockdown_off", "name": "x", "id": "a1"})
        (kind, payload), _ = hass.bus.async_fire.call_args
        self.assertEqual(kind, EVENT_SIDECAR)
        self.assertEqual(payload["device_id"], "tab-1")
        self.assertEqual(payload["event"], "alarm_ringing")
        self.assertEqual(payload["name"], "Kitchen tablet")
        self.assertEqual(payload["id"], "a1", "extra fields still come through")

    def test_event_data_that_is_not_a_dict_is_ignored(self):
        hass, device = make_device()
        device.handle_event("alarm_ringing", ["not", "a", "dict"])  # type: ignore[arg-type]
        (_, payload), _ = hass.bus.async_fire.call_args
        self.assertEqual(payload, {"device_id": "tab-1", "name": "Kitchen tablet", "event": "alarm_ringing"})


@unittest.skipUnless(HAVE_HA, "needs the homeassistant package")
@unittest.skipUnless(HAVE_HA, "needs the homeassistant package")
class BeaconHealDefaultTest(unittest.TestCase):
    def test_heal_is_on_unless_the_entry_saved_it_off(self):
        from custom_components.ha_sidecar.const import CONF_BEACON_HEAL

        _, device = make_device()
        self.assertTrue(device.beacon_heal_enabled)
        device.entry.options = {CONF_BEACON_HEAL: False}
        self.assertFalse(device.beacon_heal_enabled)


class SendCommandTest(unittest.IsolatedAsyncioTestCase):
    async def test_a_socket_that_closes_while_writing_is_a_home_assistant_error_and_leaves_nothing_pending(self):
        hass, device = make_device(asyncio.get_running_loop())
        ws = open_socket()
        ws.send_json.side_effect = ConnectionResetError("Cannot write to closing transport")
        device.attach(ws, {})
        with self.assertRaises(HomeAssistantError):
            await device.send_command("stop_alarm")
        self.assertEqual(device._pending, {})

    async def test_a_closed_websocket_runtime_error_is_handled_the_same_way(self):
        hass, device = make_device(asyncio.get_running_loop())
        ws = open_socket()
        ws.send_json.side_effect = RuntimeError("WebSocket connection is closed")
        device.attach(ws, {})
        with self.assertRaises(HomeAssistantError):
            await device.send_command("stop_alarm")

    async def test_push_to_a_socket_that_just_closed_does_not_raise(self):
        hass, device = make_device(asyncio.get_running_loop())
        ws = open_socket()
        ws.send_json.side_effect = ConnectionResetError("closing")
        device.attach(ws, {})
        coro = device._async_push(ws, {"type": "voice_event"})
        await coro  # must complete without an exception


@unittest.skipUnless(HAVE_HA, "needs the homeassistant package")
class TimerTwinTest(unittest.TestCase):
    def test_removing_the_satellite_takes_its_timer_twins_out_of_the_manager(self):
        from custom_components.ha_sidecar import assist_satellite as sat

        device = SimpleNamespace(device_id="tab-1", name="Kitchen tablet", state={}, voice_handler=None, connected=False)
        entity = sat.SidecarSatellite.__new__(sat.SidecarSatellite)
        manager = MagicMock()
        manager.timers = {"ha-1": object(), "ha-2": object()}
        entity.hass = MagicMock()
        entity.hass.data = {sat.TIMER_DATA: manager}
        entity._device = device
        entity._quiet = 0
        entity._mirror = {"t1": sat._Mirror("ha-1", None, 1000, False), "t2": sat._Mirror("ha-2", None, 1000, False)}
        entity._drop_twins()
        self.assertEqual({c.args[0] for c in manager.cancel_timer.call_args_list}, {"ha-1", "ha-2"})
        self.assertEqual(entity._mirror, {})
        self.assertEqual(entity._quiet, 0, "the manager's events are only muted while we change it")


@unittest.skipUnless(HAVE_HA, "needs the homeassistant package")
class WebSocketViewTest(unittest.IsolatedAsyncioTestCase):
    async def _run(self, hello, later=()):
        from custom_components.ha_sidecar import websocket_view as view

        hass, device = make_device(asyncio.get_running_loop())
        hass.data = {view.DOMAIN: {"devices": {"tab-1": device}}}
        hass.async_create_task = lambda coro: coro.close()
        messages = [SimpleNamespace(type=view.WSMsgType.TEXT, json=lambda m=m: m) for m in later]

        class Socket:
            closed = False

            async def prepare(self, request):
                pass

            async def receive_json(self, timeout=None):
                return hello

            async def send_json(self, msg):
                self.sent.append(msg)

            async def close(self):
                self.closed = True

            def __aiter__(self):
                async def gen():
                    for m in messages:
                        yield m

                return gen()

        sock = Socket()
        sock.sent = []
        view_obj = view.SidecarWebSocketView()
        original = view.web.WebSocketResponse
        view.web.WebSocketResponse = lambda **kw: sock
        try:
            request = SimpleNamespace(app={view.KEY_HASS: hass}, remote="1.2.3.4")
            await view_obj.get(request)
        finally:
            view.web.WebSocketResponse = original
        return sock, device

    async def test_a_hello_that_is_not_an_object_is_refused_quietly(self):
        sock, device = await self._run(["not", "an", "object"])
        self.assertEqual(sock.sent[0]["type"], "error")
        self.assertFalse(device.connected)

    async def test_a_device_field_that_is_not_an_object_does_not_break_the_handshake(self):
        sock, device = await self._run({"type": "hello", "protocol": 1, "token": "secret", "device": "a string"})
        self.assertEqual(sock.sent[0]["type"], "hello_ok")
        self.assertEqual(device.info, {})

    async def test_a_message_that_is_not_an_object_is_skipped_and_the_next_one_is_handled(self):
        sock, device = await self._run(
            {"type": "hello", "protocol": 1, "token": "secret"}, later=[[1, 2], {"type": "state", "state": {"screen_on": True}}]
        )
        self.assertEqual(device.state.get("screen_on"), True)


if __name__ == "__main__":
    unittest.main()
