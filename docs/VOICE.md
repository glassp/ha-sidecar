# Voice (phase 3)

The tablet becomes an Assist satellite: it records the microphone, Home Assistant runs the Assist pipeline (STT, conversation,
TTS), the tablet shows and speaks the answer. Everything runs over the existing sidecar WebSocket (see
[PROTOCOL.md](PROTOCOL.md)); no second connection, no port on the tablet.

## Slices

| Slice | What | State |
|---|---|---|
| 3.1 | Integration: `assist_satellite` entity, voice messages, announcements. Tested against a real Home Assistant with a fake tablet | done, see [TESTING.md](TESTING.md) |
| 3.2 | App: microphone capture, TTS playback, push-to-talk, answer page | done as v1 (full-screen page; the docked bubble over the dashboard is still to do) |
| 3.3 | Wake word on the device (openWakeWord models on LiteRT) | done, see below |
| 3.4 | Timers by voice, `start_conversation`, ask question, skins | not started |

## Design decisions

- **Home Assistant's own satellite API.** The entity subclasses `AssistSatelliteEntity` and calls
  `async_accept_pipeline_from_satellite`, so pipeline selection, VAD sensitivity, conversation ids, announcements and
  the Assist "satellite" automations work like for any other satellite. We do not run a pipeline ourselves.
- **Audio in: base64 PCM in JSON frames.** 16 kHz, mono, signed 16 bit little endian (what the pipeline expects), 80 ms per
  frame (1280 samples, about 3.4 KB of text, 12.5 frames per second; the size the wake word model works in). Binary frames would save a third of the bandwidth but need a second
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

## The app (slice 3.2)

- **Starting a turn:** *Talk to Assist* on the Home tab, the Home Assistant service `ha_sidecar.listen` (also the button
  *Start listening*, for a physical button or an automation) or, later, the wake word. `ha_sidecar.cancel_listening` ends it.
- **Recording:** `Voice.kt` records 16 kHz mono PCM16 with `AudioRecord` (source *voice recognition*) in a foreground
  service of type `microphone`, 80 ms per frame, with a level for the page. The page opens first, so the app is visible when the
  service starts (Android 14+ forbids starting a microphone service from the background). Recording ends on Home Assistant's
  `stt-end`/error, on *Done talking*, on cancel, or after 30 s.
- **Permission:** `RECORD_AUDIO`. A device owner grants it silently (also again after it was revoked); otherwise the
  permission dialog opens (`mic_permission` is the error shown meanwhile, with an *Allow the microphone* button).
- **Answer:** the TTS URL is fetched through the address the tablet is connected through (Home Assistant may name its internal
  address while the tablet is away), played with `MediaPlayer` (usage *assistant*, transient audio focus that lets other audio
  duck), `played` is sent when it ends.
- **The page** (`/voice`, an own Android activity like the alarm page, over the lock screen, keeps the screen on): state icon with a
  level ring, the recognised text, the answer, errors named by their stage (microphone, connection, speech recognition, playback),
  buttons *Done talking* / *Cancel*, double tap cancels. It closes itself 4 s after a turn (6 s after an error).
- **Safety:** a turn with no event from Home Assistant for 20 s is cancelled (`timeout`); losing the connection cancels it; a new
  turn interrupts the old one.

## Wake word (slice 3.3)

- **How it works:** the one microphone loop (`Voice.micLoop`) feeds 80 ms frames to the wake word engine while no turn is
  running (and to Home Assistant while one is). The engine is the openWakeWord pipeline: a mel spectrogram model, an embedding
  model and one small classifier per phrase, run with LiteRT 1.4 (`org.tensorflow.lite.Interpreter`). A score above the *Wake word
  threshold* (50 % by default) starts a turn exactly like the talk button, with the phrase passed to Home Assistant (`wake_word` in
  `start`); then the engine pauses, and for 2 s after the turn, so the answer is not heard as a new wake word.
- **Phrases:** Hey Jarvis, Alexa, Hey Mycroft (the three single-phrase openWakeWord models). The *timer* and *weather* models
  are command classifiers with other inputs and outputs and are not used.
- **Models are downloaded on the device, not shipped.** The openWakeWord code is Apache-2.0, but its pre-trained models are
  CC BY-NC-SA 4.0 (non-commercial), which does not fit this repository's Apache-2.0 licence, so the app fetches them from the
  openWakeWord GitHub release (`v0.5.1`) when the wake word is switched on: about 3.7 MB for the first phrase (the two shared
  models and the phrase), 0.9 to 1.3 MB for each further one. Every file is checked against a SHA-256 pinned in
  `WakeWord.kt` and written under `files/wakeword/` only if it matches; a failed download waits for the user's retry
  (*Download* in the status row, or the HA command `download_wake_word`). The runtime (LiteRT) is Apache-2.0 and part of the app.
- **Switching on:** *System → Voice → Wake word* in the app, the switch `switch.<prefix>_wake_word`, or choosing a wake word
  for the satellite in Home Assistant (*Settings → Voice assistants → Satellites*; the entity reports the three phrases and the
  active one, and setting it switches the wake word on). Entities: the switch, `select.<prefix>_wake_word_phrase`,
  `number.<prefix>_wake_word_threshold`, `binary_sensor.<prefix>_wake_word_listening` (diagnostic). Off by default: it keeps the
  microphone open; the persistent notification says so, and Android shows the microphone indicator.
- **The melspectrogram model needs a patched copy:** it is stored with the input shape `[1, 1]`, which its convolutions cannot be
  allocated for, and the Java interpreter allocates in its constructor. `TfliteShape` rewrites that shape in an in-memory copy
  (a minimal FlatBuffers reader); the engine resizes the input per call anyway.
- **Android limits:** a microphone foreground service can only be started from the background by a device owner (or while the app
  is visible). After a reboot the wake word therefore starts by itself on a device-owner tablet (not verified on hardware); otherwise
  the status shows *Android did not allow the microphone to start in the background* until the app is opened once.

## Not built yet

- The **docked bubble** over the dashboard (the page is full screen for now).
- More phrases (own models can be trained with openWakeWord; a custom model slot is not built), several active wake words at once.
- Wake word detection on the tablet while HA is unreachable still starts a turn that fails with *Not connected*; there is no local fallback.
- `start_conversation` and `ask_question` (the entity advertises only *announce*), timers by voice (3.4).
- Binary audio frames (base64 in JSON is used), a microphone/speaker test in the app, a volume setting, echo cancellation while
  the answer plays (the engine is paused instead).
