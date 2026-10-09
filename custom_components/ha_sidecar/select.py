"""Select entities (brightness mode, presence camera)."""

from __future__ import annotations

from homeassistant.components.assist_pipeline.select import AssistPipelineSelect, VadSensitivitySelect
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .config_entities import SELECTS, ConfigSelect
from .const import CONF_DEVICE_ID, DOMAIN
from .entity import add_entities


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    add_entities(device, "select", async_add_entities, [ConfigSelect(device, *s) for s in SELECTS])
    # the Assist pipeline and VAD sensitivity of this tablet's satellite (the satellite entity reads them)
    info = DeviceInfo(identifiers={(DOMAIN, device.device_id)})
    pipeline = SidecarPipelineSelect(hass, device.device_id, info)
    vad = SidecarVadSelect(hass, device.device_id, info)
    pipeline.entity_id = f"select.{device.entity_prefix}_assist_pipeline"
    vad.entity_id = f"select.{device.entity_prefix}_assist_vad_sensitivity"
    async_add_entities([pipeline, vad])


class SidecarPipelineSelect(AssistPipelineSelect):
    _attr_has_entity_name = True
    _attr_name = "Assist pipeline"

    def __init__(self, hass: HomeAssistant, device_id: str, info: DeviceInfo) -> None:
        super().__init__(hass, DOMAIN, device_id)
        self._attr_device_info = info


class SidecarVadSelect(VadSensitivitySelect):
    _attr_has_entity_name = True
    _attr_name = "Assist voice activity sensitivity"

    def __init__(self, hass: HomeAssistant, device_id: str, info: DeviceInfo) -> None:
        super().__init__(hass, device_id)
        self._attr_device_info = info
