"""Sensors."""

from __future__ import annotations

from datetime import datetime, timezone

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import PERCENTAGE, EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity

# key, name, device_class, unit, entity_category, icon
SENSORS = [
    ("battery_level", "Battery", SensorDeviceClass.BATTERY, PERCENTAGE, None, None),
    ("next_alarm", "Next alarm", SensorDeviceClass.TIMESTAMP, None, None, None),
    ("foreground_app", "Foreground app", None, None, None, "mdi:application"),
    ("mode", "Enforcement mode", None, None, EntityCategory.DIAGNOSTIC, "mdi:shield-lock"),
    ("security_patch", "Security patch", None, None, EntityCategory.DIAGNOSTIC, "mdi:shield-check"),
    ("android_release", "Android version", None, None, EntityCategory.DIAGNOSTIC, "mdi:android"),
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
        if self._key == "next_alarm":  # epoch millis
            return datetime.fromtimestamp(value / 1000, tz=timezone.utc)
        return value
