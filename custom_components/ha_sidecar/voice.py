"""Audio plumbing and event trimming for the voice satellite (no Home Assistant imports, unit-testable)."""

from __future__ import annotations

import asyncio
import base64
import binascii
from collections.abc import AsyncIterator
from typing import Any

MAX_FRAME_BYTES = 64 * 1024  # a frame is ~3.2 KB (100 ms); anything near this is a bug or abuse
MAX_QUEUED_FRAMES = 200  # ~20 s of audio waiting for the pipeline; more means it stopped consuming


class AudioStream:
    """Frames from the tablet, as the async iterator the Assist pipeline reads.

    `push` never blocks: the tablet must not be slowed down by Home Assistant. When the pipeline stops reading
    (it ended the run, for example after the end of speech) the queue fills up and further frames are dropped.
    """

    def __init__(self) -> None:
        self._queue: asyncio.Queue[bytes | None] = asyncio.Queue(MAX_QUEUED_FRAMES)
        self._closed = False
        self.frames = 0
        self.dropped = 0

    @property
    def closed(self) -> bool:
        return self._closed

    def push(self, data_b64: Any) -> bool:
        """Queue one base64 frame. Returns False if it was rejected or dropped."""
        if self._closed or not isinstance(data_b64, str) or len(data_b64) > MAX_FRAME_BYTES * 4 // 3 + 4:
            return False
        try:
            frame = base64.b64decode(data_b64, validate=True)
        except (binascii.Error, ValueError):
            return False
        if not frame or len(frame) % 2:  # PCM16: an odd length is a broken frame
            return False
        try:
            self._queue.put_nowait(frame)
        except asyncio.QueueFull:
            self.dropped += 1
            return False
        self.frames += 1
        return True

    def close(self) -> None:
        """No more audio (the tablet stopped recording, or the run was cancelled)."""
        if self._closed:
            return
        self._closed = True
        try:
            self._queue.put_nowait(None)
        except asyncio.QueueFull:
            # the pipeline is not reading; make room for the end marker so a late reader still terminates
            self._queue.get_nowait()
            self._queue.put_nowait(None)

    def __aiter__(self) -> AsyncIterator[bytes]:
        return self._frames()

    async def _frames(self) -> AsyncIterator[bytes]:
        while True:
            frame = await self._queue.get()
            if frame is None:
                return
            yield frame


def _dig(data: Any, *path: str) -> Any:
    for key in path:
        if not isinstance(data, dict):
            return None
        data = data.get(key)
    return data


def trim_event(event_type: str, data: dict[str, Any] | None) -> dict[str, Any]:
    """Reduce an Assist pipeline event to what the tablet's UI needs."""
    if event_type == "stt-end":
        return {"text": _dig(data, "stt_output", "text") or ""}
    if event_type == "intent-end":
        return {
            "text": _dig(data, "intent_output", "response", "speech", "plain", "speech") or "",
            "continue_conversation": bool(_dig(data, "intent_output", "continue_conversation")),
        }
    if event_type == "tts-end":
        return {"url": _dig(data, "tts_output", "url") or ""}
    if event_type == "error":
        return {"code": _dig(data, "code") or "unknown", "message": _dig(data, "message") or ""}
    return {}
