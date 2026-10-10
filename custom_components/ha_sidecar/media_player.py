"""The tablet's voice volume as a media player, so that "set the volume to 30 percent" and "louder" work by voice.

Home Assistant's volume commands (HassSetVolume, HassSetVolumeRelative) target media players, and so do dashboards and LLM
agents. This entity plays nothing: it is the handle for the volume of the voice assistant on the tablet.

During a conversation a change applies to that conversation only (the tablet goes back to the preferred voice volume when it is
over); outside a conversation it sets the preferred voice volume (the number entity of the same name).
"""

from __future__ import annotations

from homeassistant.components.media_player import MediaPlayerEntity, MediaPlayerEntityFeature, MediaPlayerState
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity, add_entities

STEP_PERCENT = 10


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    add_entities(device, "media_player", async_add_entities, [SidecarVoiceVolume(device)])


class SidecarVoiceVolume(SidecarEntity, MediaPlayerEntity):
    _attr_name = "Voice"
    _attr_icon = "mdi:account-voice"
    _attr_supported_features = MediaPlayerEntityFeature.VOLUME_SET | MediaPlayerEntityFeature.VOLUME_STEP
    _attr_volume_step = STEP_PERCENT / 100

    def __init__(self, device) -> None:
        super().__init__(device, "voice_volume_player")

    @property
    def state(self) -> MediaPlayerState:
        return MediaPlayerState.IDLE

    @property
    def volume_level(self) -> float | None:
        value = (self._state.get("cfg") or {}).get("voice_volume")
        return None if value is None else float(value) / 100

    async def async_set_volume_level(self, volume: float) -> None:
        await self._device.send_command("voice_volume", {"percent": round(volume * 100)})

    async def async_volume_up(self) -> None:
        await self._device.send_command("voice_volume", {"delta": STEP_PERCENT})

    async def async_volume_down(self) -> None:
        await self._device.send_command("voice_volume", {"delta": -STEP_PERCENT})
