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
            SidecarBrightness(device),
            *(ConfigLevelNumber(device, *lv) for lv in LEVELS),
            *(ConfigNumber(device, *n) for n in NUMBERS),
        ]
    )


class SidecarBrightness(SidecarEntity, NumberEntity):
    """Current screen brightness, settable (percent; raw 0..255 with the developer option)."""

    _attr_name = "Screen brightness (manual)"
    _attr_icon = "mdi:brightness-6"
    _attr_native_min_value = 0
    _attr_native_step = 1

    def __init__(self, device) -> None:
        super().__init__(device, "brightness")

    @property
    def _raw_mode(self) -> bool:
        return bool((self._state.get("cfg") or {}).get("raw_brightness"))

    @property
    def native_max_value(self) -> float:
        return 255 if self._raw_mode else 100

    @property
    def native_unit_of_measurement(self) -> str | None:
        return None if self._raw_mode else "%"

    @property
    def native_value(self) -> float | None:
        value = self._state.get("brightness")
        return value if self._raw_mode else pct_from_raw(value)

    async def async_set_native_value(self, value: float) -> None:
        await self._device.send_command("set_brightness", {"level": int(value) if self._raw_mode else raw_from_pct(value)})
