"""The tablet as an Assist satellite (see docs/VOICE.md)."""

from __future__ import annotations

import asyncio
import logging
from typing import Any

from homeassistant.components.assist_pipeline import PipelineEvent, PipelineStage
from homeassistant.components.assist_satellite import (
    AssistSatelliteAnnouncement,
    AssistSatelliteConfiguration,
    AssistSatelliteEntity,
    AssistSatelliteEntityFeature,
    AssistSatelliteWakeWord,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import ANNOUNCE_TIMEOUT, CONF_DEVICE_ID, DOMAIN
from .entity import SidecarEntity, add_entities
from .voice import AudioStream, trim_event

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    device = hass.data[DOMAIN]["devices"][entry.data[CONF_DEVICE_ID]]
    add_entities(device, "assist_satellite", async_add_entities, [SidecarSatellite(device)])


class _Run:
    """One push-to-talk turn: the tablet's id for it, its audio and the task running the pipeline."""

    def __init__(self, session: str, stream: AudioStream) -> None:
        self.session = session
        self.stream = stream
        self.task: asyncio.Task | None = None


class SidecarSatellite(SidecarEntity, AssistSatelliteEntity):
    _attr_name = "Assist"
    _attr_icon = "mdi:microphone-message"
    _attr_supported_features = AssistSatelliteEntityFeature.ANNOUNCE

    def __init__(self, device) -> None:
        super().__init__(device, "assist")
        self._incoming: _Run | None = None  # the newest requested run: it receives the tablet's audio
        self._active: _Run | None = None  # the run that is executing: its pipeline events are what we forward

    # --- settings that live in other entities --------------------------------------------------------

    @property
    def pipeline_entity_id(self) -> str | None:
        return er.async_get(self.hass).async_get_entity_id(Platform.SELECT, DOMAIN, f"{self._device.device_id}-pipeline")

    @property
    def vad_sensitivity_entity_id(self) -> str | None:
        return er.async_get(self.hass).async_get_entity_id(Platform.SELECT, DOMAIN, f"{self._device.device_id}-vad_sensitivity")

    # --- lifecycle -----------------------------------------------------------------------------------

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        self._device.voice_handler = self._handle_voice

    async def async_will_remove_from_hass(self) -> None:
        if self._device.voice_handler == self._handle_voice:
            self._device.voice_handler = None
        self._end_session()

    @callback
    def _handle_update(self) -> None:
        if not self._device.connected:
            self._end_session()  # nobody is listening to the answer any more
        super()._handle_update()

    # --- configuration (wake words arrive with the on-device engine, slice 3.3) ----------------------

    @callback
    def async_get_configuration(self) -> AssistSatelliteConfiguration:
        """The phrases the tablet can listen for (the app knows its catalogue) and the one that is on."""
        known = self._device.state.get("wake_words") or []
        cfg = self._device.state.get("cfg") or {}
        active = [cfg["wake_word_id"]] if cfg.get("wake_word") and cfg.get("wake_word_id") else []
        return AssistSatelliteConfiguration(
            available_wake_words=[
                AssistSatelliteWakeWord(id=w["id"], wake_word=w.get("phrase") or w["id"], trained_languages=["en"])
                for w in known
                if isinstance(w, dict) and "id" in w
            ],
            active_wake_words=active,
            max_active_wake_words=1,
        )

    async def async_set_configuration(self, config: AssistSatelliteConfiguration) -> None:
        """Choosing a phrase in Home Assistant switches the wake word on (the tablet fetches the models it lacks by itself)."""
        if not config.active_wake_words:
            await self._device.send_command("set_config", {"config": {"wake_word": False}})
            return
        wanted = config.active_wake_words[0]
        await self._device.send_command("set_config", {"config": {"wake_word_id": wanted, "wake_word": True}})


    # --- tablet -> Home Assistant --------------------------------------------------------------------

    @callback
    def _handle_voice(self, msg: dict[str, Any]) -> None:
        action, session = msg.get("action"), msg.get("session")
        if not isinstance(session, str) or not session:
            return
        run = self._incoming if self._incoming is not None and self._incoming.session == session else None
        if action == "start":
            self._start_session(session, msg.get("wake_word") if isinstance(msg.get("wake_word"), str) else None)
        elif action == "audio" and run is not None:
            run.stream.push(msg.get("data"))
        elif action == "stop" and run is not None:
            run.stream.close()
        elif action == "cancel" and run is not None:
            self._end_session()
        elif action == "played" and session in (self._incoming and self._incoming.session, self._active and self._active.session):
            self.tts_response_finished()

    @callback
    def _start_session(self, session: str, wake_word: str | None) -> None:
        previous = self._incoming
        self._end_session()  # a new start interrupts the running one
        run = _Run(session, AudioStream())
        self._incoming = run
        run.task = self.hass.async_create_background_task(
            self._run_pipeline(run, previous.task if previous else None, wake_word), f"{self.entity_id}_voice_{session}"
        )

    @callback
    def _end_session(self) -> None:
        run, self._incoming = self._incoming, None
        if run is not None:
            run.stream.close()
            if run.task is not None and not run.task.done():
                run.task.cancel()

    async def _run_pipeline(self, run: _Run, previous: asyncio.Task | None, wake_word: str | None) -> None:
        if previous is not None:
            # the cancelled run still emits its closing events; let it finish so they are not tagged with this session
            await asyncio.gather(previous, return_exceptions=True)
        self._active = run
        try:
            await self.async_accept_pipeline_from_satellite(
                audio_stream=run.stream, start_stage=PipelineStage.STT, end_stage=PipelineStage.TTS, wake_word_phrase=wake_word
            )
        except asyncio.CancelledError:
            raise
        except Exception as err:  # noqa: BLE001 - tell the tablet instead of leaving it listening
            _LOGGER.warning("Assist run for %s failed: %s", self._device.name, err)
            self._send(run.session, "error", {"code": "pipeline-failed", "message": str(err)})
        finally:
            run.stream.close()
            if self._incoming is run:
                self._incoming = None

    # --- Home Assistant -> tablet --------------------------------------------------------------------

    @callback
    def on_pipeline_event(self, event: PipelineEvent) -> None:
        kind = event.type.value
        self._send(self._active.session if self._active else None, kind, trim_event(kind, event.data))

    def _send(self, session: str | None, event: str, data: dict[str, Any]) -> None:
        self._device.push({"type": "voice_event", "session": session, "event": event, "data": data})

    async def async_announce(self, announcement: AssistSatelliteAnnouncement) -> None:
        await self._device.send_command(
            "voice_announce",
            {
                "url": announcement.media_id,
                "message": announcement.message,
                "preannounce_url": announcement.preannounce_media_id,
            },
            timeout=ANNOUNCE_TIMEOUT,
        )
