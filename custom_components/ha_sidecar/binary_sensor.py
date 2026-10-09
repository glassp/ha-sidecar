"""Binary sensors."""

from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity, add_entities

# key, name, device_class, entity_category, icon
SENSORS = [
    ("presence", "Presence", BinarySensorDeviceClass.PRESENCE, None, None),
    ("camera_motion", "Camera motion", BinarySensorDeviceClass.MOTION, None, None),
    ("camera_active", "Presence camera running", None, EntityCategory.DIAGNOSTIC, "mdi:camera"),
    ("glance_showing", "Glance screen showing", None, None, "mdi:clock-digital"),
    ("is_night", "Night", None, None, "mdi:weather-night"),
    ("alarm_ringing", "Alarm ringing", None, None, "mdi:alarm-light"),
    ("timer_ringing", "Timer ringing", None, None, "mdi:timer-alert"),
    ("camera_in_use", "Camera in use", BinarySensorDeviceClass.RUNNING, None, "mdi:camera"),
    ("mic_in_use", "Microphone in use", BinarySensorDeviceClass.RUNNING, None, "mdi:microphone"),
    ("is_home_app", "Is home app", None, EntityCategory.DIAGNOSTIC, "mdi:home"),
    ("device_owner", "Device owner", None, EntityCategory.DIAGNOSTIC, "mdi:shield-account"),
    ("accessibility_enabled", "Accessibility guard", None, EntityCategory.DIAGNOSTIC, "mdi:human"),
    ("overlay_granted", "Overlay permission", None, EntityCategory.DIAGNOSTIC, "mdi:layers"),
    ("write_settings_granted", "Modify system settings permission", None, EntityCategory.DIAGNOSTIC, "mdi:cog"),
]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    add_entities(device, "binary_sensor", async_add_entities, [*(SidecarBinarySensor(device, *s) for s in SENSORS), CompanionResponsiveSensor(device), DashboardResponsiveSensor(device)])


class SidecarBinarySensor(SidecarEntity, BinarySensorEntity):
    def __init__(self, device, key, name, device_class, category, icon) -> None:
        super().__init__(device, key)
        self._attr_name = name
        self._attr_device_class = device_class
        self._attr_entity_category = category
        self._attr_icon = icon

    @property
    def is_on(self) -> bool | None:
        value = self._state.get(self._key)
        return None if value is None else bool(value)


class CompanionResponsiveSensor(SidecarEntity, BinarySensorEntity):
    """Is the Home Assistant app responding? Unknown while it is not in front or the watchdog is off."""

    _attr_name = "Companion app responsive"
    _attr_icon = "mdi:heart-pulse"

    def __init__(self, device) -> None:
        super().__init__(device, "companion_responsive")

    @property
    def is_on(self) -> bool | None:
        return (self._state.get("watchdog") or {}).get("responsive")


class DashboardResponsiveSensor(SidecarEntity, BinarySensorEntity):
    """Is the dashboard on the tablet alive? Needs a beacon card on the dashboard; unknown until its first ping."""

    _attr_name = "Dashboard responsive"
    _attr_icon = "mdi:monitor-eye"

    def __init__(self, device) -> None:
        super().__init__(device, "dashboard_responsive")

    @property
    def is_on(self) -> bool | None:
        state = self._device.beacon_state
        return {"ok": True, "stale": False}.get(str(state))

    @property
    def extra_state_attributes(self) -> dict[str, str]:
        return {"beacon": str(self._device.beacon_state)}
