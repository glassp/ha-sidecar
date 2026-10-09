"""Switches: kiosk lockdown, keep screen on."""

from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from .config_entities import SWITCHES, ConfigSwitch
from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    async_add_entities(
        [
            SidecarSwitch(device, "lockdown", "Kiosk lockdown", "set_lockdown", "mdi:lock"),
            SidecarSwitch(device, "keep_screen_on", "Keep screen on", "set_keep_screen_on", "mdi:brightness-7"),
            SidecarSwitch(device, "kiosk_launcher", "Act as home app", "set_kiosk_launcher", "mdi:home-lock"),
            AlarmsMutedSwitch(device),
            *(ConfigSwitch(device, *s) for s in SWITCHES),
        ]
    )


class SidecarSwitch(SidecarEntity, SwitchEntity):
    def __init__(self, device, key: str, name: str, command: str, icon: str) -> None:
        super().__init__(device, key)
        self._attr_name = name
        self._attr_icon = icon
        self._command = command

    @property
    def is_on(self) -> bool | None:
        value = self._state.get(self._key)
        return None if value is None else bool(value)

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._device.send_command(self._command, {"enabled": True})

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._device.send_command(self._command, {"enabled": False})


class AlarmsMutedSwitch(SidecarSwitch):
    """Mutes every alarm (they keep their schedule). Turn on = until turned off; use `ha_sidecar.mute_alarms` for a duration."""

    def __init__(self, device) -> None:
        super().__init__(device, "alarms_muted", "Alarms muted", "mute_alarms", "mdi:bell-sleep")

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        until = self._state.get("alarms_muted_until")
        return {"muted_until": dt_util.utc_from_timestamp(until / 1000) if until else None}

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._device.send_command("mute_alarms", {})

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._device.send_command("unmute_alarms", {})
