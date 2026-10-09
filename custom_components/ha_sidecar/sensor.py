"""Sensors."""

from __future__ import annotations

from datetime import datetime, timezone

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity

# key, name, device_class, unit, entity_category, icon
# (battery, charging, Android version, security patch, next alarm and storage are already exposed by the
# Home Assistant companion app, so they are intentionally not duplicated here)
SENSORS = [
    ("last_interaction", "Last interaction", SensorDeviceClass.TIMESTAMP, None, None, "mdi:gesture-tap"),
    ("foreground_app", "Foreground app", None, None, None, "mdi:application"),
    ("target_brightness", "Target brightness", None, None, EntityCategory.DIAGNOSTIC, "mdi:brightness-percent"),
    ("last_blocked_app", "Last blocked app", None, None, EntityCategory.DIAGNOSTIC, "mdi:shield-alert"),
    ("blocked_count", "Blocked app launches", None, None, EntityCategory.DIAGNOSTIC, "mdi:counter"),
    ("pin_failures", "PIN failures", None, None, EntityCategory.DIAGNOSTIC, "mdi:lock-alert"),
    ("mode", "Enforcement mode", None, None, EntityCategory.DIAGNOSTIC, "mdi:shield-lock"),
]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    async_add_entities(SidecarSensor(device, *s) for s in SENSORS)


class SidecarSensor(SidecarEntity, SensorEntity):
    def __init__(self, device, key, name, device_class, unit, category, icon) -> None:
        super().__init__(device, key)
        self._attr_name = name
        self._attr_device_class = device_class
        self._attr_native_unit_of_measurement = unit
        self._attr_entity_category = category
        self._attr_icon = icon

    @property
    def native_value(self):
        value = self._state.get(self._key)
        if value is None:
            return None
        if self._key == "last_interaction":  # epoch millis
            return datetime.fromtimestamp(value / 1000, tz=timezone.utc)
        return value
