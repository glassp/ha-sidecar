# Voice (phase 3)

The tablet becomes an Assist satellite: it records the microphone, Home Assistant runs the Assist pipeline (STT, conversation,
TTS), the tablet shows and speaks the answer. Everything runs over the existing sidecar WebSocket (see
[PROTOCOL.md](PROTOCOL.md)); no second connection, no port on the tablet.

## Slices

| Slice | What | State |
|---|---|---|
| 3.1 | Integration: `assist_satellite` entity, voice messages, announcements. Tested against a real Home Assistant with a fake tablet | done, see [TESTING.md](TESTING.md) |
| 3.2 | App: microphone capture, TTS playback, push-to-talk, answer overlay | not started |
| 3.3 | Wake word on the device (`WakeWordEngine`, openWakeWord via TFLite) | not started |
| 3.4 | Timers by voice, `start_conversation`, ask question, skins | not started |

## Design decisions

- **Home Assistant's own satellite API.** The entity subclasses `AssistSatelliteEntity` and calls
  `async_accept_pipeline_from_satellite`, so pipeline selection, VAD sensitivity, conversation ids, announcements and
  the Assist "satellite" automations work like for any other satellite. We do not run a pipeline ourselves.
- **Audio in: base64 PCM in JSON frames.** 16 kHz, mono, signed 16 bit little endian (what the pipeline expects), 100 ms per
  frame (about 4.3 KB of text, 10 frames per second). Binary frames would save a third of the bandwidth but need a second
  parser on both sides; revisit if a real network shows a problem.
- **Audio out: Home Assistant's TTS URL.** Home Assistant sends the URL (a signed `/api/tts_proxy/...` path), the tablet
  fetches it from the address it is already connected to and plays it. The tablet confirms when playback ended
  (`played`), which is what returns the entity from *responding* to *idle*.
- **One session at a time.** A new `start` cancels a running one (barge-in); a disconnect cancels it.
- **Push-to-talk first, wake word later.** `start` has an optional `wake_word` phrase for slice 3.3; without it the
  pipeline starts at STT.
- **The tablet stops recording when Home Assistant says so** (`stt-end`, or an error), not on its own VAD. Home Assistant
  already runs VAD (`pymicro_vad`) and the silence length is the entity's *VAD sensitivity* setting.

## Messages

Tablet to Home Assistant, all `{"type": "voice", "action": ..., "session": "<id chosen by the tablet>"}`:

| action | extra fields | meaning |
|---|---|---|
| `start` | `wake_word` (optional phrase) | begin a pipeline run, audio follows |
| `audio` | `data` (base64 PCM) | one frame |
| `stop` | | the tablet stopped recording (button released, timeout) |
| `cancel` | | abort the run |
| `played` | | the TTS answer finished playing |

Home Assistant to the tablet:

- `{"type": "voice_event", "session": id, "event": <pipeline event>, "data": {...}}` with the pipeline event names of
  Assist (`run-start`, `stt-start`, `stt-vad-start`, `stt-vad-end`, `stt-end`, `intent-start`, `intent-end`, `tts-start`,
  `tts-end`, `run-end`, `error`). `data` is trimmed to what the UI needs: `stt-end` `{text}`, `intent-end`
  `{text, continue_conversation}`, `tts-end` `{url}`, `error` `{code, message}`.
- Command `voice_announce` `{url, message, preannounce_url}`: play the sound, then the announcement; the result is sent when
  playback ended (so Home Assistant can block, as the satellite API requires).

State of the entity follows the pipeline: `idle`, `listening` (from `stt-start`), `processing` (from `intent-start`),
`responding` (from `tts-start` until `played`).

## Entities (per tablet, prefix `lab` as example)

`assist_satellite.lab_assist` (features: announce), `select.lab_assist_pipeline` (which Assist pipeline; *preferred* by
default) and `select.lab_assist_vad_sensitivity` (how long a pause ends the command). These are Home Assistant's own helper
selects, the satellite entity reads them like it does for ESPHome or VoIP devices.

## What is not in 3.1

- No wake word: `async_get_configuration` reports no available wake words, `async_set_configuration` does nothing.
- `start_conversation` and `ask_question` (the entity advertises only *announce*).
- The app side: nothing records or plays yet, so with the real app the entity stays *idle* and an announcement times out
  after 120 s. See slice 3.2.
