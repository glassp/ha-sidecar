"""TTS that returns a short tone for any text."""

import io
import math
import struct
import wave

from homeassistant.components.tts import TextToSpeechEntity


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([LabTTS()])


class LabTTS(TextToSpeechEntity):
    _attr_name = "Lab TTS"
    _attr_unique_id = "lab_voice_tts"
    _attr_default_language = "en"
    _attr_supported_languages = ["en"]

    async def async_get_tts_audio(self, message, language, options):
        rate, seconds = 16000, 0.8
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
            w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / rate))) for i in range(int(rate * seconds))))
        return "wav", buf.getvalue()
