"""Select entities (brightness mode, presence camera)."""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .config_entities import SELECTS, ConfigSelect
from .const import CONF_DEVICE_ID, DOMAIN
from .entity import add_entities


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    add_entities(device, "select", async_add_entities, [ConfigSelect(device, *s) for s in SELECTS])
