"""STT that "recognises" a fixed phrase whenever it receives audio (LAB_VOICE_PHRASE, default "what time is it")."""

import os

from homeassistant.components.stt import (
    AudioBitRates, AudioChannels, AudioCodecs, AudioFormats, AudioSampleRates,
    SpeechMetadata, SpeechResult, SpeechResultState, SpeechToTextEntity,
)


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([LabSTT()])


class LabSTT(SpeechToTextEntity):
    _attr_name = "Lab STT"
    _attr_unique_id = "lab_voice_stt"

    @property
    def supported_languages(self): return ["en"]
    @property
    def supported_formats(self): return [AudioFormats.WAV]
    @property
    def supported_codecs(self): return [AudioCodecs.PCM]
    @property
    def supported_bit_rates(self): return [AudioBitRates.BITRATE_16]
    @property
    def supported_sample_rates(self): return [AudioSampleRates.SAMPLERATE_16000]
    @property
    def supported_channels(self): return [AudioChannels.CHANNEL_MONO]

    async def async_process_audio_stream(self, metadata: SpeechMetadata, stream) -> SpeechResult:
        total = 0
        async for chunk in stream:
            total += len(chunk)
        if total == 0:
            return SpeechResult("", SpeechResultState.ERROR)
        return SpeechResult(os.environ.get("LAB_VOICE_PHRASE", "what time is it"), SpeechResultState.SUCCESS)
