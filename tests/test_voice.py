"""Unit tests for the voice plumbing: python3 -m unittest discover -s tests"""

import asyncio
import base64
import importlib.util
import sys
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "voice", Path(__file__).parent.parent / "custom_components" / "ha_sidecar" / "voice.py"
)
voice = importlib.util.module_from_spec(SPEC)
sys.modules["voice"] = voice
SPEC.loader.exec_module(voice)


def frame(n: int = 1600) -> str:
    return base64.b64encode(bytes(range(256)) * (n * 2 // 256) + bytes(n * 2 % 256)).decode()


async def collect(stream):
    return [f async for f in stream]


class AudioStreamTest(unittest.IsolatedAsyncioTestCase):
    async def test_frames_come_out_in_order_and_end_on_close(self):
        s = voice.AudioStream()
        a, b = base64.b64encode(b"\x01\x00" * 10).decode(), base64.b64encode(b"\x02\x00" * 10).decode()
        self.assertTrue(s.push(a))
        self.assertTrue(s.push(b))
        s.close()
        self.assertEqual(await collect(s), [b"\x01\x00" * 10, b"\x02\x00" * 10])

    async def test_a_reader_waiting_for_audio_is_released_by_close(self):
        s = voice.AudioStream()
        task = asyncio.create_task(collect(s))
        await asyncio.sleep(0)
        s.close()
        self.assertEqual(await asyncio.wait_for(task, 1), [])

    async def test_bad_frames_are_rejected(self):
        s = voice.AudioStream()
        self.assertFalse(s.push("not base64!!"))
        self.assertFalse(s.push(None))
        self.assertFalse(s.push(base64.b64encode(b"\x00").decode()), "odd length is not PCM16")
        self.assertFalse(s.push(""))
        self.assertFalse(s.push("A" * 200_000), "oversized")
        self.assertEqual(s.frames, 0)

    async def test_push_never_blocks_and_drops_when_nobody_reads(self):
        s = voice.AudioStream()
        results = [s.push(frame(160)) for _ in range(voice.MAX_QUEUED_FRAMES + 5)]
        self.assertEqual(results.count(False), 5)
        self.assertEqual(s.dropped, 5)

    async def test_close_with_a_full_queue_still_terminates_the_reader(self):
        s = voice.AudioStream()
        for _ in range(voice.MAX_QUEUED_FRAMES):
            s.push(frame(160))
        s.close()
        frames = await asyncio.wait_for(collect(s), 1)
        self.assertEqual(len(frames), voice.MAX_QUEUED_FRAMES - 1)

    async def test_nothing_is_accepted_after_close(self):
        s = voice.AudioStream()
        s.close()
        s.close()  # idempotent
        self.assertFalse(s.push(frame(160)))
        self.assertEqual(await collect(s), [])


class TrimEventTest(unittest.TestCase):
    def test_stt_end(self):
        self.assertEqual(voice.trim_event("stt-end", {"stt_output": {"text": "what time is it"}}), {"text": "what time is it"})

    def test_intent_end(self):
        data = {"intent_output": {"response": {"speech": {"plain": {"speech": "It is noon."}}}, "continue_conversation": True}}
        self.assertEqual(voice.trim_event("intent-end", data), {"text": "It is noon.", "continue_conversation": True})

    def test_tts_end(self):
        self.assertEqual(voice.trim_event("tts-end", {"tts_output": {"url": "/api/tts_proxy/x.mp3", "mime_type": "audio/mpeg"}}), {"url": "/api/tts_proxy/x.mp3"})

    def test_error(self):
        self.assertEqual(voice.trim_event("error", {"code": "stt-no-text-recognized", "message": "x"}), {"code": "stt-no-text-recognized", "message": "x"})

    def test_missing_or_odd_data_never_raises(self):
        for kind in ("stt-end", "intent-end", "tts-end", "error"):
            voice.trim_event(kind, None)
            voice.trim_event(kind, {"stt_output": "oops", "intent_output": [], "tts_output": 3})
        self.assertEqual(voice.trim_event("run-start", {"anything": 1}), {})


if __name__ == "__main__":
    unittest.main()
