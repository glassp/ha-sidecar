"""Screen brightness."""

from __future__ import annotations

from homeassistant.components.number import NumberEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    async_add_entities([SidecarBrightness(device)])


class SidecarBrightness(SidecarEntity, NumberEntity):
    _attr_name = "Screen brightness"
    _attr_icon = "mdi:brightness-6"
    _attr_native_min_value = 0
    _attr_native_max_value = 255
    _attr_native_step = 1

    def __init__(self, device) -> None:
        super().__init__(device, "brightness")

    @property
    def native_value(self) -> float | None:
        return self._state.get("brightness")

    async def async_set_native_value(self, value: float) -> None:
        await self._device.send_command("set_brightness", {"level": int(value)})
