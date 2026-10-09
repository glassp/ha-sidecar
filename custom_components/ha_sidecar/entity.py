"""Shared entity base."""

from __future__ import annotations

from homeassistant.core import callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.entity import Entity

from .const import DOMAIN
from .device import SidecarDevice


class SidecarEntity(Entity):
    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, device: SidecarDevice, key: str) -> None:
        self._device = device
        self._key = key
        self._attr_unique_id = f"{device.device_id}_{key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, device.device_id)},
            name=device.name,
            manufacturer=device.info.get("manufacturer"),
            model=device.info.get("model"),
        )

    @property
    def available(self) -> bool:
        return self._device.connected

    @property
    def _state(self) -> dict:
        return self._device.state

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(async_dispatcher_connect(self.hass, self._device.signal, self._handle_update))

    @callback
    def _handle_update(self) -> None:
        self.async_write_ha_state()
