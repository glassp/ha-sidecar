"""Screen brightness and numeric settings."""

from __future__ import annotations

from homeassistant.components.number import NumberEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .config_entities import LEVELS, NUMBERS, ConfigLevelNumber, ConfigNumber, pct_from_raw, raw_from_pct
from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity, add_entities


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    add_entities(device, "number", async_add_entities, 
        [
            SidecarBrightness(device, raw=False),
            SidecarBrightness(device, raw=True),
            *(ConfigLevelNumber(device, *lv, raw) for lv in LEVELS for raw in (False, True)),
            *(ConfigNumber(device, *n) for n in NUMBERS),
        ]
    )


class SidecarBrightness(SidecarEntity, NumberEntity):
    """Current screen brightness, settable: `Screen brightness percentage` (0-100) and `Screen brightness raw` (0-255)."""

    _attr_icon = "mdi:brightness-6"
    _attr_native_min_value = 0
    _attr_native_step = 1

    def __init__(self, device, raw: bool) -> None:
        super().__init__(device, f"brightness_{'raw' if raw else 'percentage'}")
        self._raw = raw
        self._attr_name = f"Screen brightness {'raw' if raw else 'percentage'}"
        self._attr_native_max_value = 255 if raw else 100
        self._attr_native_unit_of_measurement = None if raw else "%"

    @property
    def native_value(self) -> float | None:
        value = self._state.get("brightness")
        return value if self._raw else pct_from_raw(value)

    async def async_set_native_value(self, value: float) -> None:
        await self._device.send_command("set_brightness", {"level": int(value) if self._raw else raw_from_pct(value)})
