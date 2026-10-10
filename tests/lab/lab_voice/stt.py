"""STT that "recognises" a fixed phrase whenever it receives audio. The phrase is read at every call from the file named by
LAB_VOICE_PHRASE_FILE (default /tmp/lab_voice_phrase.txt), so a test can change what the "user" says without restarting;
an empty file means "nothing was understood". Without the file LAB_VOICE_PHRASE or "what time is it" is used."""

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
        path = os.environ.get("LAB_VOICE_PHRASE_FILE", "/tmp/lab_voice_phrase.txt")
        if os.path.exists(path):
            phrase = open(path).read().strip()
            if not phrase:
                return SpeechResult("", SpeechResultState.ERROR)
        else:
            phrase = os.environ.get("LAB_VOICE_PHRASE", "what time is it")
        return SpeechResult(phrase, SpeechResultState.SUCCESS)
