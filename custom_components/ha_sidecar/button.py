"""Buttons."""

from __future__ import annotations

from homeassistant.components.button import ButtonDeviceClass, ButtonEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity

# key, name, command, device_class, category, icon
BUTTONS = [
    ("wake_screen", "Wake screen", "screen", {"on": True}, None, None, "mdi:monitor-shimmer"),
    ("sleep_screen", "Sleep screen", "screen", {"on": False}, None, None, "mdi:monitor-off"),
    ("bring_to_front", "Bring dashboard to front", "bring_to_front", {}, None, None, "mdi:monitor-dashboard"),
    ("stop_alarm", "Stop alarm", "stop_alarm", {}, None, None, "mdi:alarm-off"),
    ("snooze_alarm", "Snooze alarm", "snooze_alarm", {}, None, None, "mdi:alarm-snooze"),
    ("run_system_update", "Run system update", "run_system_update", {}, None, EntityCategory.CONFIG, "mdi:cellphone-arrow-down"),
    ("open_system_update", "Open system update", "open_system_update", {}, None, EntityCategory.CONFIG, "mdi:system-update"),
    ("reboot", "Reboot", "reboot", {}, ButtonDeviceClass.RESTART, EntityCategory.CONFIG, None),
]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    async_add_entities(SidecarButton(device, *b) for b in BUTTONS)


class SidecarButton(SidecarEntity, ButtonEntity):
    def __init__(self, device, key, name, command, data, device_class, category, icon) -> None:
        super().__init__(device, key)
        self._attr_name = name
        self._command = command
        self._data = data
        self._attr_device_class = device_class
        self._attr_entity_category = category
        self._attr_icon = icon

    async def async_press(self) -> None:
        await self._device.send_command(self._command, self._data)
