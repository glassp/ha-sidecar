"""The tablet as an Assist satellite (see docs/VOICE.md)."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from typing import Any

from homeassistant.components.assist_pipeline import PipelineEvent, PipelineStage
from homeassistant.components.intent.timers import (
    TimerEventType,
    TimerInfo,
    async_register_timer_handler,
)
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
from homeassistant.exceptions import HomeAssistantError
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
    _attr_supported_features = AssistSatelliteEntityFeature.ANNOUNCE | AssistSatelliteEntityFeature.START_CONVERSATION

    def __init__(self, device) -> None:
        super().__init__(device, "assist")
        self._incoming: _Run | None = None  # the newest requested run: it receives the tablet's audio
        self._active: _Run | None = None  # the run that is executing: its pipeline events are what we forward
        self._unregister_timers: Callable[[], None] | None = None

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
        # "set a timer for 5 minutes" is answered by Home Assistant's timer intents; this is where it hands the timer over
        if self.registry_entry and self.registry_entry.device_id:
            self._unregister_timers = async_register_timer_handler(self.hass, self.registry_entry.device_id, self._on_timer)

    async def async_will_remove_from_hass(self) -> None:
        if self._device.voice_handler == self._handle_voice:
            self._device.voice_handler = None
        if self._unregister_timers is not None:
            self._unregister_timers()
            self._unregister_timers = None
        self._end_session()

    @callback
    def _handle_update(self) -> None:
        if not self._device.connected:
            self._end_session()  # nobody is listening to the answer any more
        super()._handle_update()

    # --- configuration (wake words arrive with the on-device engine, slice 3.3) ----------------------

    @callback
    def async_get_configuration(self) -> AssistSatelliteConfiguration:
        """The phrases the tablet can listen for (its app knows the catalogue) and the ones that are on."""
        known = [w for w in self._device.state.get("wake_words") or [] if isinstance(w, dict) and "id" in w]
        cfg = self._device.state.get("cfg") or {}
        chosen = [i.strip() for i in str(cfg.get("wake_word_ids") or "").split(",") if i.strip()]
        known_ids = {w["id"] for w in known}
        return AssistSatelliteConfiguration(
            available_wake_words=[
                AssistSatelliteWakeWord(id=w["id"], wake_word=w.get("phrase") or w["id"], trained_languages=["en"]) for w in known
            ],
            active_wake_words=[i for i in chosen if i in known_ids] if cfg.get("wake_word") else [],
            max_active_wake_words=max(len(known), 1),
        )

    async def async_set_configuration(self, config: AssistSatelliteConfiguration) -> None:
        """Choosing phrases in Home Assistant switches the wake word on (the tablet fetches the models it lacks by itself)."""
        ids = list(dict.fromkeys(config.active_wake_words))
        if not ids:
            await self._device.send_command("set_config", {"config": {"wake_word": False}})
            return
        await self._device.send_command("set_config", {"config": {"wake_word_ids": ",".join(ids), "wake_word": True}})

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

    # --- voice timers: Home Assistant's timer manager -> the tablet's own timers ---------------------

    @callback
    def _on_timer(self, event: TimerEventType, timer: TimerInfo) -> None:
        self.hass.async_create_task(self._async_timer(event, timer))

    async def _async_timer(self, event: TimerEventType, timer: TimerInfo) -> None:
        """Mirror a voice timer on the tablet, which counts, shows and rings it by itself (also while Home Assistant is away)."""
        try:
            if event in (TimerEventType.STARTED, TimerEventType.UPDATED):
                # an update (time added or removed, paused, resumed) is a restart with what is left: the tablet keeps the id
                await self._device.send_command(
                    "start_timer",
                    {"id": timer.id, "label": timer.name or "", "kind": "countdown", "duration_s": max(1, timer.seconds_left)},
                )
                if not timer.is_active:
                    await self._device.send_command("pause_timer", {"id": timer.id})
            elif event == TimerEventType.CANCELLED:
                await self._device.send_command("cancel_timer", {"id": timer.id})
            elif event == TimerEventType.FINISHED:
                known = {t.get("id") for t in self._device.state.get("timers") or []}
                if timer.id not in known:  # the tablet missed it (offline, restarted): ring now
                    await self._device.send_command(
                        "start_timer", {"id": timer.id, "label": timer.name or "", "kind": "countdown", "duration_s": 1}
                    )
        except HomeAssistantError as err:
            _LOGGER.debug("Could not mirror timer %s (%s) on %s: %s", timer.id, event, self._device.name, err)

    async def async_start_conversation(self, start_announcement: AssistSatelliteAnnouncement) -> None:
        """Play the announcement, then the tablet listens by itself (used by start_conversation and ask_question)."""
        await self._device.send_command(
            "voice_conversation",
            {
                "url": start_announcement.media_id,
                "message": start_announcement.message,
                "preannounce_url": start_announcement.preannounce_media_id,
            },
            timeout=ANNOUNCE_TIMEOUT,
        )

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
