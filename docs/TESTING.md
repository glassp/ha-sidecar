# Test log and how to reproduce

Last full run: 2026-10-10 (beacon, pairing reconnect and service sweep; earlier parts 2026-10-09), emulator `ha_sidecar_tablet` (Android 15 / API 35 google_apis arm64, tablet 2560x1800)
+ Home Assistant Core 2026.10.0 (venv, Python 3.14) + HA companion app 2026.8.4 (`app-minimal-release.apk`).
A physical phone joined on 2026-10-10 (Pixel 6, Android 17, over Wi-Fi adb): see *Pixel 6 run* below. No physical *tablet* yet.

## Verified on the emulator

| Area | Result |
|---|---|
| Integration loads in HA 2026.10.0, config flow (name → token) creates 23 entities | ✅ |
| Pairing (URL + token), handshake, state push, reconnect after app/HA restart | ✅ |
| Wrong/missing token | ✅ `auth_failed`, app stops retrying |
| Remote lockdown without PIN | ✅ refused (`pin_required`) |
| Device owner: `dpm set-device-owner` | ✅ |
| Device-owner lockdown: HA app in lock-task (`mLockTaskModeState=LOCKED`), status bar/nav gone, Home/Recents/other apps/shade blocked | ✅ |
| Hot corner (5 taps top-left) opens PIN pad while locked; correct PIN ends lock-task and turns the HA switch off | ✅ |
| PIN cooldown (5 wrong → 30 s, correct PIN rejected during cooldown, accepted after) | ✅ |
| Accessibility fallback: Home/Recents/browser/Settings bounced back to the HA app, shade closed | ✅ (bounce takes 1-4 s on the slow emulator, system UI is briefly visible) |
| Foreground-app sensor (accessibility) | ✅ |
| Alarm: HA service → native alarm → rings (full screen + heads-up + ALARM stream) → snooze → rings again → stop; bus events `alarm_ringing` / `alarm_stopped` | ✅ |
| Remote screen sleep (`lockNow`) and wake, brightness | ✅ |
| `bring_to_front` (with and without `homeassistant://navigate/` path), `launch_app`, error for missing package | ✅ |
| Reboot with lockdown on, nobody opens the UI: sidecar reconnects to HA ≈25 s after boot and relaunches the HA app into lock-task | ✅ |
| System update button: opens Google's update screen, stays in front under lockdown (temporary allowlist) | ✅ |
| Update automation: arm → tap → events (`started`/`step`/`finished`), click cap + idle timeout | ✅ (only the "check for update" label; the emulator has no update to download/install) |

### Launcher / lifecycle run (added later the same day)

| Area | Result |
|---|---|
| Accessibility route: Home button → HA app directly (no stock launcher flash); `set-home-activity` was used to pick the sidecar | ✅ |
| Force-stop the HA app → home → HA app back (3/3), also under lockdown | ✅ |
| Reboot, nobody touches the tablet: Android starts the sidecar as home, HA app in front, HA reconnected | ✅ |
| Device-owner route: enabling *Act as home app* from HA makes the sidecar the home app with **no** manual step (`is_home_app` off → on) | ✅ |
| Device-owner lockdown: force-stop HA app → back in lock-task (`LOCKED`) in 4-5 s, 3/3 | ✅ |
| Reboot with DO + lockdown + launcher: HA app in lock-task without interaction | ✅ |

Observed flakiness (emulator, heavily loaded Mac): one recovery right after first enabling launcher mode ended on the
stock launcher, and fixed-delay sampling sometimes caught the transition; polling shows 4-5 s recovery. After a reboot
the emulator once lost its network (not the app; the client reconnected on its own once Wi-Fi was toggled).

### Display / presence / glance run

| Area | Result |
|---|---|
| Brightness: `day` level, idle dim after `Dim after`, wake on HA presence (input_boolean), hold time, back to dim | ✅ |
| Touch detection through the 1px overlay (`last_interaction`, wakes from dim) | ✅ (HA shows the timestamp with up to 10 s delay; brightness reacts immediately) |
| Night: base level, night light with presence, brightness after touch + hold, night light switch off | ✅ |
| Options flow (presence + glance entities), entry reload | ✅ |
| Camera presence: device owner grants the permission silently, service starts from a background command, motion toggles (emulated camera), own camera excluded from `camera_in_use` | ✅ |
| Glance screen over lock-task: appears after idle, touch dismisses, presence dismisses (slowly on the emulator), not shown while present | ✅ |
| `App theme` select: dark on a light system, light, dark-at-night in night/day | ✅ (screenshots) |
| Failed PIN → `pin_failed` events and `PIN failures` sensor | ✅ |

Bugs found: glance state was not pushed when the screen appeared/disappeared; glance values showed raw ISO timestamps and
repeated the device name (both fixed); `Camera app` on the emulator image cannot hold the camera, so `camera_in_use` and
`mic_in_use` stay **unverified**; `app_blocked` / `guard_disabled` need the accessibility route and were not re-run.

### Dashboard mode run

| Area | Result |
|---|---|
| `DashboardPath` URL normalizer + deep-link builder: 15 JVM unit tests (`./gradlew :app:testDebugUnitTest`) | ✅ |
| Lockdown refused without a kiosk dashboard (`dashboard_required`) | ✅ |
| Pasting `https://home.glassp.dev/lovelace/wall-panel` into the HA text entity stores `lovelace/wall-panel`; host-only URL rejected with a clear error | ✅ |
| Lockdown start launches the companion app's `LinkActivity` with the deep link, in lock-task | ✅ |
| Glance dashboard: after idle the companion is sent to the glance path, touch and presence send it back to the kiosk path, `Glance screen showing` follows | ✅ (intent level) |
| Empty glance dashboard falls back to the native clock screen | ✅ |

**Not verified:** that a *signed-in* companion app actually switches dashboards on `homeassistant://navigate/...` while it is
already running (the emulator's companion app is not logged in; entering credentials there was out of scope). Android
redacts the deep-link URI in logs, so the exact path is covered by the unit tests, not by the device log. Please check this
once on your real tablet; if the companion app only handles it on cold start, the glance mode needs a different approach.

### Freeze spike (design input for roadmap 2.5)

Companion app frozen with `kill -STOP` on the emulator: accessibility dump fails with a null root within ~3 s; touching it
brings the system ANR dialog ("Home Assistant isn't responding", Close app / Wait) in ~2 s; "Close app" kills the process;
`pm suspend` does not kill a stopped process but `pm hide` does and `unhide` + launch restores a healthy app with data
intact. Not tried: the real `DevicePolicyManager` calls, a renderer-only hang, a cold-start hang.

### UI redesign run (emulator, hot-reload session)

| Area | Result |
|---|---|
| Setup wizard stepped through end to end; Home / Kiosk / Display / System / Alarms tabs, settings search ("night light" returns the night light, its brightness, mode, theme, permission), language switch to German (labels, tab names, search hints) | ✅ screenshots |
| PIN pad, idle screen as Flutter pages in the single activity (`--es route /pin`, `/glance`), back/cancel/touch close them | ✅ |
| 15 Kotlin + 8 Dart tests (incl. translation key parity en/de and "every used key exists") | ✅ |

Bugs found: a second/third Flutter activity on the shared engine detached the main one (black screen) → single activity with
routes; the splash drew the adaptive launcher icon as a bitmap and crashed at start → dedicated splash PNG; `BeamPage` with a
reused key never updates its child → the shell reads the tab from the router; beamer stacks parent routes → `stacked: false`.
Not verified: alarm page while an alarm really rings over the lock screen, PIN unlock round trip through the new page, wizard
permission buttons (they open Android settings), phone-sized layout.

### Timers and remote alarm control (emulator + throwaway HA)

| Area | Result |
|---|---|
| `start_timer` / `start_stopwatch` / `pause` / `resume` / `adjust` / `cancel` via HA services, by label and by id; `sensor.timers`, `next_timer` | ✅ |
| Countdown finishes: rings, `timer_finished` event on the HA bus, ring page shows "Time's up" and the overtime counting up, `stop_alarm` dismisses (`timer_dismissed`) | ✅ |
| `mute_alarms` (switch on, event); a muted alarm fires silently (`alarm_skipped`, `reason: muted`, `binary_sensor.alarm_ringing` stays off); `unmute_alarms` | ✅ |
| `skip_next_alarm` on a repeating alarm moves `next` by one day (`skip_next` attribute) | ✅ |
| 5 Kotlin unit tests (timer arithmetic, skip-next) | ✅ |

Bugs found: the ringing page and the idle screen never ticked because their clock timer was a lazy `late final` that nothing
started; a second timer finishing while one rings replaced the first one's sound, so it now stays listed as finished instead.
Not verified: timers over a reboot / Doze, countdown on the idle screen visually, voice interaction (not built yet; it will
call the same platform methods).

### Pairing, discovery and network policy (emulator + throwaway HA)

| Area | Result |
|---|---|
| Tablet pairing mode: port 8750 opens, code and addresses shown, mDNS registration succeeds (`NsdManager` callback) | ✅ |
| HA config flow by address + code (`adb forward`): unreachable host -> `cannot_connect`; wrong code -> `bad_token` (counts toward the 5-try lock); malformed prefix rejected; right code -> entry created, tablet saved the new token and addresses and connected, entities live | ✅ |
| Confirm mode: HA and tablet showed the same comparison number (387 497), Allow on the tablet + submit in HA -> entry created, tablet connected | ✅ |
| Kotlin and Python crypto agree (HKDF, HMAC proof, AES-GCM, comparison number) on shared vectors; round trip and tamper detection | ✅ (4 Kotlin tests) |
| *Home network only* with VPN-as-home on, tablet on Wi-Fi (not home): connection dropped (entities unavailable); back to *Always*: reconnected | ✅ |
| Route choice (internal/external/waiting/offline) for Wi-Fi, Ethernet, VPN, cellular, nothing configured | ✅ (7 Dart tests) |

Bugs found: org.json `optString` turns a JSON null into the string `"null"` (the external address became "null"); a stale
text field did not follow a value changed by pairing.
**Not verified:** actual mDNS discovery by Home Assistant (the emulator's NAT does not bridge multicast; zeroconf step
reviewed only), the Deny and timeout paths, Wi-Fi name matching (needs the location permission and a real SSID), a real VPN,
two tablets, IPv6-only networks.

### Companion app watchdog (emulator, Android 15, companion 2026.8.4, process frozen with `kill -STOP`)

| Area | Result |
|---|---|
| Healthy app in front: probe sees its window (16 accessibility nodes), no action over several minutes | ✅ |
| Frozen UI (`ui_frozen`): window cannot be read, three bad probes in a row; with a 5 s interval recovery ran about 30 s after the freeze, with ~20 s about 70-80 s | ✅ |
| Recovery as device owner: hide + unhide + relaunch took ~3.5 s; new process, healthy tree, in front | ✅ (7 times) |
| ANR dialog: after a touch the system showed "Home Assistant isn't responding" ~15-25 s later; the probe saw package `android` with `android:id/aerr_close`, tapped "Close app" (`anr_close`), relaunched | ✅ |
| Rate limit: three restarts within 10 minutes, the fourth freeze was detected and **not** restarted (`giving up ... after 3 restarts`, state `gave_up`, `companion_restart_gave_up` event) | ✅ |
| Settings UI: switch, action, interval and start-up sliders, status tile | ✅ screenshots |

Bugs found: the accessibility call goes to the frozen app and can block for a long time, which stalled the watchdog thread
once -> probes now run on a worker thread with an 8 s timeout (no answer = bad probe); a process that froze while still
starting never reported a window, so no probe ran -> after a launch we issued the app is expected for the start-up window;
the `gave_up` state was overwritten by the idle gating -> it now persists. The relaunch with a kiosk dashboard uses the
`homeassistant://navigate/...` deep link, which crashed the (not signed-in) companion in this lab; recovery then ended with the
sidecar in front and the app dead (that is F4, handled only in lockdown by the home role).
**Not verified:** gating while the screen is off / an alarm rings / the PIN is open (code only), false positives on a healthy
device over a day (dimming, glance, Wi-Fi changes), a start-up hang that is *not* a frozen UI (F1 proper), the non-device-owner
paths (`relaunch_only`), the Home Assistant entities (the integration was only compiled; the test Home Assistant was removed
before this phase), a physical tablet and localized ANR dialogs.

### Dashboard beacon: integration, tablet and ladder (emulator, real Home Assistant 2026.10)

Run against a throwaway Home Assistant (pip install, loopback only, throwaway user created through the onboarding API, token via
the WebSocket API; the companion app was never signed in) and the emulator. The tablet was paired with the manual code flow
(`user` -> `details`), entity prefix `lab`; the card file is served (`/ha_sidecar_static/ha-sidecar-beacon-card.js`, 200,
`text/javascript`); `ha_sidecar/tablets` lists the tablet; `ha_sidecar/beacon` answers. A script stood in for the card
(pings over the WebSocket API); options: heal on, timeout 1 min. Companion app in front, screen on.

| Case | Result |
|---|---|
| warm-up after the entry loads | `paused` for 2 min, then `ok` on the next ping |
| pings stop without a goodbye, no kiosk dashboard set | stale after ~60 s + the 30 s tick (`dashboard_unresponsive`), then `heal_dashboard` straight away: companion restarted, restart counter +1 with reason `beacon` |
| same, kiosk dashboard set | `dashboard_unresponsive` and `dashboard_navigate_attempt` in the same tick, the heal ~2 min later (the 90 s retry, rounded up by the tick), counter +1 |
| first ping after an episode | `dashboard_recovered` fires once |
| card says goodbye (`inactive`) | no `dashboard_unresponsive`, no navigate, no restart in 200 s |

**Not verified (this part):** whether the navigate intent really lands in a signed-in companion app. In this lab the navigate
attempt makes the not-signed-in companion app misbehave (ANR dialogs, restarts by the watchdog), so the restart counts above
include those.

#### With the real card, in a real Home Assistant frontend

A storage-mode dashboard `kiosk-test` (view *Home* with the card `tablet: lab`, `interval: 10`, plus an entities card; view
*Other* without a card) was opened in the desktop app's built-in browser, logged in through a loopback-only `trusted_networks`
provider (no credentials typed). The companion app on the emulator was in front; the lab tablet had heal on, timeout 1 min.
The browser pane is hidden inside the desktop app (`visibilityState` hidden, animation frames throttled), which makes the card
refuse to ping by design, so the page's `visibilityState` and `requestAnimationFrame` were shimmed to emulate a visible
WebView. Nothing else in the page was touched.

| Case | Result |
|---|---|
| card on the dashboard | **failed at first**: "Custom element doesn't exist". Home Assistant swaps in a scoped-registry polyfill for `customElements` *after* extra modules ran, and only looks cards up there; the element was defined, but in the old registry. Fixed: the card waits for the frontend's own `ha-card` before defining (new Node test); renders after that |
| pings from the real card | `ok`, path `/kiosk-test/home`, last-beacon sensor updates |
| switch to the view without the card | `inactive`, reason `navigation`, then `card removed from the page`; still `inactive` after 2+ minutes, no event, no restart |
| back to the view with the card | `ok` again |
| the page's JavaScript thread blocked for 270 s (a real freeze, no goodbye) | stale ~96 s after the hang, `dashboard_unresponsive` and `dashboard_navigate_attempt` in the same tick, `heal_dashboard` ~2 min later: `companion_unresponsive`, restart counter +1, `companion_restarted`, reason `beacon` |
| editor | `getStubConfig` picks the registered tablet; the editor lists `Lab Tablet (lab)`; choosing it emits `config-changed` with `tablet: lab` (driven by script against the real `hass`, not by clicking through the dashboard editor) |

Still **not** verified: the card inside the companion app's own WebView (the companion app was never signed in), the editor
used through the dashboard UI by hand, and the false-positive rate over days.

#### Service sweep against the tablet (16 checks, all passing)

`start_timer` ("batch 1"), `pause_timer`, `resume_timer`, `adjust_timer`, `cancel_timer`, `start_stopwatch`, a short timer that
finishes (event `timer_finished`, ringing sensor on), `set_alarm`, `mute_alarms` and `unmute_alarms` (switch follows), `skip_next_alarm`,
`set_alarm_enabled`, `cancel_alarm`, brightness projection both ways (50 % -> raw 128, raw 100 -> 39 %), `exit_night_mode` (day) and
`enter_night_mode` (night) with `follow_schedule`, a switch, the kiosk dashboard text, the *bring dashboard to front* button and
`launch_app`. Two checks first looked like failures and were wrong expectations: a `treadmill` stopwatch from an earlier session
already existed (same label = same timer, so the count does not change), and `enter_night_mode` does not change the brightness
*mode* select (it forces the night state; the select stays `manual`).

Found on the way: after a completed pairing the app did not reconnect until its process was restarted. Cause:
`SidecarClient.stop()` awaited `sink.close()` on a channel whose connection had failed ("not upgraded", as before the integration
exists), which never completes, so the re-pairing's client restart hung. Fixed (`stop()` no longer waits, a connect that finishes
after `stop()` is dropped); `test/sidecar_client_test.dart` reproduces it (3 tests, failed before the fix); re-checked on the
emulator by pairing while the tablet sat in that state: it connected by itself. Home Assistant 2026.10 reverts an unconfirmed `http:` config after 5 minutes and restarts itself (exit code 100), so a
test harness must restart it on that code; on macOS the `pyobjc` CoreBluetooth binding gets the Home Assistant process killed
when it has no Bluetooth permission (remove the package or the `bluetooth` integration for lab runs).

### Voice, integration side (slice 3.1)

`tests/lab/voice_fake.py` is a fake tablet that speaks the voice protocol against the lab Home Assistant (needs the real tablet
offline: `adb shell cmd connectivity airplane-mode enable`, because a reconnecting tablet takes the connection back) with the
`tests/lab/lab_voice` component providing STT (always "recognises" a fixed phrase when it gets audio) and TTS (a tone) and a
pipeline using them. 26 checks pass: the entity is idle on connect; a full turn (`start`, 1 s of 100 ms frames, `stop`) gives
`stt-start`, `stt-end` (text), `intent-end` (the built-in agent answers "what time is it"), `tts-end` (URL that plays, 200 and
audio) and `run-end`; the state goes `listening`, `processing`, `responding`, back to `idle` on `played`; `assist_satellite.announce`
reaches the tablet as `voice_announce` with the URL, message and pre-announce sound and blocks until the tablet answers;
barge-in (a new `start` cancels the running turn, no event of the old run is tagged with the new session); `cancel`; garbage
(bad base64, odd-length PCM, missing fields, frames for unknown sessions) is ignored; a disconnect makes the entity unavailable and
ends the turn, and a turn after reconnecting works. The barge-in check found a real bug on the first run (the cancelled run's closing
`run-end` was tagged with the new session, so the tablet would have taken the new turn for finished); a new run now starts only after the
old one ended. Unit tests (`tests/test_voice.py`, 11) cover the audio queue (order, close, back-pressure, bad frames) and the event trimming.

### With an LLM agent (Ollama, emulator, lab Home Assistant)

Ollama (`brew install ollama`, loopback only) with `llama3.2:3b` (2 GB) as the Lab pipeline's conversation agent, Assist API on; two floors, four
rooms with a temperature sensor each (`tests/lab/llm_setup.py`; HA's Ollama integration needs `pip install ollama==0.6.2` in the lab venv).
On an 8 GB Mac the model, the emulator and Home Assistant together swap heavily (an Android "not responding" dialog appeared once).

- **A voice turn through the LLM works end to end:** "what is the temperature in the kitchen" was answered "The temperature in the kitchen is 21.5°C."
  after about 34 s of thinking, spoken, and the tablet listened for a follow-up. This found a bug: the app's 20 s watchdog gave up on the
  silent thinking stage; it now has its own limit of 120 s (`thinkTimeout`, one controller test).
- **The model is the limit, not the satellite:** the 3B model failed "what is the average temperature on each floor" (said it had no data) and once
  called the broadcast tool by itself. A bigger model or a cloud agent is needed for aggregation; a template sensor per floor does it without one.
- Not run: `start_conversation` with the LLM agent, conversation context across follow-ups with a capable model.

Not verified: real speech (the lab STT ignores the audio content), a real VAD end-of-speech (the fake tablet ends the turn itself),
any of the app side.

### Voice, app side (slice 3.2, emulator, the real app against the lab Home Assistant)

Home Assistant service `ha_sidecar.listen` (and the app's *Talk to Assist* action) on the real tablet app, lab STT/TTS:
the assistant page opens over the app, the Android microphone indicator comes on, the entity goes `listening`; *Done talking*
(or, with silence, Home Assistant's own end-of-listening after about 15 s) gives `responding` with the recognised text and the
answer on screen, the tone is played (an `AudioTrack` with the delivered frames shows in the log), the entity returns to `idle`
within about 3 s of the tap and the recording service is gone. Also checked: the *Cancel* button and `ha_sidecar.cancel_listening`
end a turn (entity `idle`, no recording service); two `listen` calls in a row (barge-in); `assist_satellite.announce` plays the pre-announce
sound and the message and the service call returns when the tablet finished (5.9 s including speech generation); the microphone
permission revoked with `pm revoke` (this kills the app process) is granted again silently by the device-owner path on the next
`listen`; the connection lost in the middle of a turn (airplane mode) cancels the recording and closes the page on the tablet,
Home Assistant notices the dead socket only after its 30 s heartbeat and then the entity is idle again after reconnecting. 13
Dart unit tests (`test/voice_controller_test.dart`) cover the controller (a full turn, address rewriting, microphone and
connection errors, stale events, barge-in, errors, timeout, disconnect, cancel while speaking, announce order and failure).

Not verified: real speech and a real microphone (the emulator's microphone delivers silence or host audio, the lab STT ignores the
content), the permission dialog for a non-device-owner install, a physical tablet's speaker and echo,
wake word (not built).

### The docked card and the timers card (slice 3.5, emulator, lab Home Assistant)

Chrome on the emulator (passwordless trusted-network login to the lab) stood in for the companion app's dashboard; the card is the
sidecar app's own overlay window, so it does not matter what is behind it.

- **Docked card:** `ha_sidecar.listen` while the dashboard was in front drew the card at the bottom (listening, waveform, *Done talking*, *End conversation*);
  "Done talking" took the turn on, the card showed what was said and the answer ("12:29 PM") with *End conversation*; the
  dashboard stayed where it was. Tapping the card brought the full page forward with the same conversation (already speaking).
  Five turns in a row, each with a tap on *Done talking*: five times the satellite went on to answering. (This found a bug: the buttons were rebuilt
  with every snapshot and presses were lost; also the card was a little transparent. Both fixed.)
- **Timers card** in the real Home Assistant frontend (a test dashboard): running, paused, finished (red) and a stopwatch tile, each ticking; clicking pause on
  one, +1 min on another and dismiss on the finished one reached the tablet (states and remaining time checked on the entity).
- **Tests:** 9 more controller tests (docked or page, fallback without permission, expand, buttons, error, throttling) and 9 JS tests for the card
  (`node --test tests/js`: registration, tiles and buttons, hiding, unknown tablet, the time maths, no rebuild on a tick, the service calls).

Not verified: the card on a real tablet with the HA companion app in front, the overlay with only an accessibility service (no "draw over other apps"),
a microphone started from a docked card on Android 14+ when the app is not a device owner, the timers card in the companion app's WebView.

### Voice volume (slice 3.6, emulator, lab Home Assistant)

Media volume read with `cmd media_session volume --stream 3 --get` (range 0..15):

- A voice turn with the preferred volume at 50 %: 3 before, **8 during**, **3 after** (the previous level restored).
- `media_player.volume_set` / `volume_up` outside a conversation set the preferred volume (30, then 40) and left the device volume at 3.
- The same call during a conversation: 6 (the preferred 40 %) -> **12 (80 %)**, the preferred volume stayed 40, and after the conversation the volume was 3 again.
- A spoken command ("set the volume to 80 percent", the lab STT hearing the phrase, the tablet assigned to an area): the volume went to 12 during the conversation,
  the card's slider showed 80 %, and afterwards 3 / preferred 40.
- 4 more controller tests (raised before the first sound, kept between turns, restored once, 0 = silent, slider and commands for the conversation only,
  relative steps, preferred outside a conversation).

Not verified: the sound itself (the emulator has no speaker to listen to), devices whose media stream is fixed or whose volume the system locks.

### Result cards and skins (slice 3.7, emulator, lab Home Assistant with the `demo` integration)

- **Cards through the satellite:** "turn on the kitchen light" answered "Turned on the switch" with a *Kitchen light - On* card; "what's the weather like" gave the weather
  card (21.6 °C, sunny, humidity / wind / pressure and a four-day forecast with the right icons) on the docked card, which kept answer and card on screen while it waited for the follow-up.
  (Home Assistant only exposes weather to Assist when you expose it; the lab needed that.)
- **`ha_sidecar.show_card`:** a camera (the demo camera's picture loaded into the docked card), a media player (title, artist - album, *Playing*), and a hand-made card
  (title, value, subtitle) appeared on their own over the dashboard, without a conversation (no status line, no waveform) and closed after their `duration`.
- **Skins:** all five were captured on the docked card and on the full-screen page. This found a bug: the page read the skin when it was first built and stayed in
  Midnight when the setting changed; it now rebuilds with the controller (test: *a skin chosen while the page is open applies at once*).
- **Tests:** 14 Python tests for the card builder (`tests/test_cards.py`), 18 Dart tests for the skins (every skin readable by WCAG contrast, palette strings, theme) and 12 for the
  cards (parsing and tolerance, cards for a turn that is no longer the current one, picture paths rebased, `show_card` with and without a conversation, the page rendering all four card types,
  the follow-up behaviour). The card parser had a bug the test found (a malformed `details` threw instead of being ignored).

Not verified: card pictures from an external URL or with a slow link, the cards with an LLM agent (they need `show_card`), very long forecasts or names (the card ellipsizes), and the
native card's glyph fallback when a picture cannot be loaded.

### The lab and the emulator (notes from this session)

- **Python crash at exit.** Stopping the lab Home Assistant crashed the interpreter while it tore its modules down (a compiled extension; `Py_Finalize` -> `finalize_modules`), and
  macOS showed "Python quit unexpectedly" every time (21 reports). Start the lab with `tests/lab/run_hass.py` (it lets Home Assistant shut down, flushes the logs and leaves with `os._exit`) and stop it
  with SIGTERM: no crash report any more.
- **"HA Sidecar isn't responding" on the emulator.** It appeared when the emulator itself was starved (17 Chrome tabs from the test scripts; the same stall showed in SystemUI and Chrome:
  hundreds of skipped frames, our app 45). Measured with the app idle: main thread 4-9 % of a core, the wake word thread about 12 %. Use one Chrome tab (`--es com.android.browser.application_id`).

### Wake word (slice 3.3, emulator)

- **The engine against a reference.** `tests/lab/wakeword/reference.py` is a Python port of the openWakeWord pipeline (LiteRT for
  Python); the app's debug-only broadcast `dev.glassp.ha_sidecar.WW_SCORE` runs the Kotlin engine over the same wavs (macOS `say`
  speech with a second of silence around it) and logs a score per 80 ms chunk. Over 9 file/phrase pairs (the phrase, other phrases
  and ordinary sentences, for all three phrases) the two agree to within 0.00005 on every chunk from the 16th on; the phrase scores
  about 1.0 and everything else below 0.001. (A first comparison disagreed because the debug reader treated afconvert's padded wav
  header as audio; the engine was right.)
- **The model patch.** The melspectrogram model could not be loaded on Android at first (`CONV_2D failed to prepare`, its stored input
  shape `[1, 1]`), which is what `TfliteShape` works around.
- **Runtime download from the app, verified.** Switching the wake word on from Home Assistant (with no models on the tablet) downloaded the
  three files (3.7 MB) from the GitHub release in about 4 s, checked their SHA-256 and sizes, and the listening sensor and the microphone
  service came on. Choosing Alexa in Home Assistant's satellite configuration (`assist_satellite/set_wake_words`) fetched only that model
  (0.86 MB) and switched the phrase. With the network off, choosing a phrase that is not on the tablet and switching the wake word on
  shows *The wake word models are not on this tablet, 0.8 MB are downloaded from GitHub once* with a Download button, and no partial
  file is left; with the network back the button downloads it and the phrase works.
- **The whole chain on the real app.** `WW_INJECT` plays a wav into the microphone loop like speech: "Hey Jarvis" starts a turn
  (answer page, HA turn with the phrase, spoken answer, back to idle) within about 1 s of the phrase; "Alexa", "Hey Mycroft", "turn on the
  kitchen light please" and a long sentence mentioning Jarvis start nothing; after switching to Alexa, "Hey Jarvis" no longer reacts and
  "Alexa" does; the wake word keeps listening after a turn; switching it off releases the microphone (service gone, no indicator).
  Home Assistant's `assist_satellite/get_configuration` reports the three phrases and the active one.

**Several phrases and the model manager (emulator).** The catalogue grew from 3 to 21 phrases. Every candidate was fetched at its pinned
revision and vetted with `tests/lab/wakeword/check_models.py` (all take `[1,16,96]` and return one score; macOS speech in two voices):
Computer, GLaDOS, Hey KITT, Hey Nabu, Hey Rhasspy, Jarvis, Marvin scored 0.99 to 1.0; Alfred, Hey Friday, Hey House, Hey Spock, Home
Assistant, Mr. Anderson, OK Computer, OK Home, OK Jarvis, OK Nabu, Terminator 0.8 to 0.93; *Hal* and *Skynet* stayed below 0.01 and were left
out. Overlapping phrases react to each other (Jarvis and OK Jarvis, Computer and OK Computer, Hey Nabu and OK Nabu). On the real app:
the dialog lists all phrases with size and status; ticking Alexa and Jarvis and Computer queued the downloads (each file verified); HA's
satellite configuration reports 21 phrases and the active ones, and choosing three at once from HA (`set_wake_words`: GLaDOS, Hey KITT,
Marvin) downloaded them and each fired with its own id (0.995 to 0.997) while an installed but unchosen phrase (Jarvis) and an unchosen one (OK
Nabu) did not; Alexa, Jarvis, Hey Jarvis and Computer fired when chosen; removing Computer in the dialog deleted its file, took it out of the
selection (HA sees it) and it stopped reacting. The first run of the dialog lost choices when three phrases were ticked in quick succession
(each tap computed the new list from a status that had not refreshed yet); the dialog now keeps its own selection and writes in order (widget
test `quick successive ticks do not undo each other`). Tests: 5 dialog widget tests, 4 Kotlin tests for the catalogue (unique ids and files, every
download pinned by hash, community files by commit).

Not verified: a real microphone, a real speaker and distances/noise (all audio here is clean `say` speech injected in software),
false activations over days (the first number to watch on a real tablet), CPU and battery of the always-open microphone, the
foreground-service start after a reboot, 16 KB page-size devices (the LiteRT 1.4 libraries are used as published).

### Conversations, voice timers and the voice screen (slice 3.4, emulator, lab Home Assistant)

Scenes were run on the real app with the lab STT "hearing" a phrase from a file (`LAB_VOICE_PHRASE_FILE`) and `say` speech played into
the microphone loop, so the waveform moves; frames were captured every ~1.2 s (`e2e/scene.py`, `e2e/conv.py` in the lab, not shipped).

- **A whole conversation without a button.** `ha_sidecar.listen`: start ping, "what time is it" (spoken), HA's voice detection ended the
  turn, the answer was shown and spoken, the tablet listened again by itself ("Listening for a follow-up", the first exchange dimmed above,
  a new dots bubble, an *End conversation* button), "set a timer for 2 minutes called tea" (spoken) got its answer and a timer pill, the
  tablet listened a third time, nothing was said, the draining bar ran out after the 8 s window and the screen closed. Pings in the log: start,
  start, start, end.
- **Timers by voice.** "Set a timer for 3 minutes called pasta" (HA's built-in timer intent) put a native timer on the tablet (label `pasta`, 180 s,
  running) and a pill on the screen; "pause the pasta timer" paused it (pill dimmed with a pause icon, 1:48 stays); "set a timer for 25 seconds"
  added a second pill; when it ended the tablet rang by itself ("Time's up", +0:03 over, *+1 min* / *Dismiss*).
- **Other scenes:** a long answer wraps in its bubble; "turn on the kitchen light" switched `input_boolean.kitchen_light`; an empty
  STT result gives a red bubble with *Talk again* and *Close*; `assist_satellite.announce` shows the message and the speaking waveform;
  `assist_satellite.ask_question` played the question, listened, returned `{id: yes, sentence: "yes please"}` to the automation, and kept the question
  on screen above the waiting answer bubble.
- **Tests:** 22 Dart tests for the controller (the loop, the pings before the microphone opens, the follow-up window, speech detection by
  HA's events and by loud frames, ending, follow-ups off, pings off, turns kept and trimmed) and 7 widget tests for the screen (bubbles, pills, paused and
  finished timers, error, the follow-up listening).

Not verified: real speech (the lab STT ignores the audio), the HA voice detection on noisy rooms (the silence length is HA's *VAD sensitivity*), how the
pings sound on a real speaker (they were only seen in the log), `start_conversation` with an LLM agent, voice timers when the tablet is offline when
they finish (code only), and the mirror of tablet timers (`ha_sidecar.start_timer` timers, also ones that existed before HA restarted, were answered by "how long is left on my timer" with the right time and the paused one counted) was checked only for those two cases, not for every voice command on a mirrored timer.

## Not verified

- Update **detection** (`onSystemUpdatePending`) and the download/install/restart taps: need a real pending OTA.
- `install_system_update` with an OTA zip, `reboot`.
- Real hardware: OEM launchers/recents, Fire tablets, Android 13/14/16, battery/doze behavior over days.
- Whether `homeassistant://navigate/` actually switches dashboards in a *signed-in* companion app (only the intent routing was checked).
- HACS/hassfest validators (they run in CI on GitHub).

## Bugs found by this run (all fixed)

1. `lockNow()` failed: `force-lock` policy missing from `device_admin.xml`. Policy changes need re-provisioning (see PROVISIONING.md).
2. The HA connection only lived while the activity existed → now a process-wide headless Flutter engine (`SidecarEngine`).
3. `setAlarmClock` needs `USE_EXACT_ALARM` on Android 13+; also an alarm was persisted even if scheduling failed.
4. Lock-task is only applied to a task that is *started* with the option → HA app is restarted once when lockdown is enabled.
5. PIN screen stayed open after unlock (own package still on the lock-task list).
6. After reboot lockdown was not re-entered.
7. Foreground app never reached HA state.
8. Update automation re-tapped a persistent "Check for update" button for the whole session.
9. Error messages repeated the error code.

## Reproduce

```bash
# emulator (Android Studio JDK needed for avdmanager)
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
avdmanager create avd -n ha_sidecar_tablet -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_c
emulator -avd ha_sidecar_tablet -no-snapshot-save

# apps
cd app && flutter build apk --debug && adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 install -r app-minimal-release.apk          # HA companion from github.com/home-assistant/android/releases
adb -s emulator-5554 shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver

# Home Assistant (separate venv; the integration is symlinked into <config>/custom_components/)
python3.14 -m venv venv && venv/bin/pip install homeassistant && venv/bin/hass -c ./config
# in the app use http://10.0.2.2:8123 (host loopback as seen from the emulator)
```

Emulator caveats: a freshly wiped AVD is very slow for several minutes (adb `input` stalls), a device owner cannot be
removed or uninstalled (wipe the AVD), `screencap` shows black for the PIN screen (`FLAG_SECURE`; use
`uiautomator dump` to find buttons), and the emulator's timezone/clock follows the host.

## Lab Home Assistant

The throwaway Home Assistant keeps its data directory between runs (`ha/config`, with the onboarded throwaway user); it only
needs a clean state when a test depends on one (for example "no integration loaded"). Boot it on loopback with
`python tests/lab/run_hass.py -c config --skip-pip` (a wrapper around `hass`, see *The lab and the emulator* below: it avoids a crash of the interpreter at exit) inside a restart-on-exit-100 loop, in a background task of its own (a detached `nohup` child dies with
the shell). For the browser, add a loopback-only `trusted_networks` auth provider (with `allow_bypass_login`) instead of seeding tokens or typing a password, and finish onboarding through its API. Remove the sidecar config entry through the API to re-pair; a manual flow left half-way blocks new ones until HA
restarts, because the progress list hides user-started flows.

## Pixel 6 run (physical phone, Android 17, 2026-10-10)

Wi-Fi adb, `adb reverse tcp:8123` to the lab Home Assistant (so the phone's `127.0.0.1:8123` is the Mac's) and `adb forward tcp:8750`
for pairing. The phone is *not* a tablet (1080x2400, 360 dp wide), which is why it found layout bugs the tablet emulator never would.
Speaker volumes were capped at about 20 % (`cmd audio set-volume`, preferred voice volume 20 %).

| Area | Result |
|---|---|
| Discovery by mDNS on a real LAN (`_ha-sidecar._tcp`), configuration flow, matching six-digit number and Allow on the phone | ✅ (never run on a real network before) |
| Setup wizard (sensors-only path), the five tabs, permission rows (write settings, notifications, battery, full-screen alarms) | ✅ walked through |
| 97 entities created; remote lockdown without a PIN refused (`pin_required`) | ✅ |
| Camera presence: front camera, motion on/off with the hold time, "permission needed" state before the grant | ✅ |
| Timer and alarm: ring on the alarm stream at a low volume, snooze and stop from HA, one-time alarm removed | ✅ (heard by the tester) |
| Voice turn: microphone permission state, docked card, answer, follow-up, volume 2 → 5 → 2 restored | ✅ (lab STT answers a fixed phrase, see *The lab*) |
| Kiosk lock (accessibility guard, no device owner): other apps bounced, Home goes back, hot corner → PIN pad, wrong PIN counted, right PIN unlocks | ✅ |
| Companion app signed in to the lab (needs `mobile_app:` in the lab config; trusted-network login, no password) | ✅ |
| Idle screen (built-in clock) | ✅ after the fix below |
| Notification shade / quick settings pulled down slowly, fast, and from the quick-settings side, with the lock on | ✅ never visible in frames (see below) |
| Back pressed 10 times at 0.1–0.8 s intervals with the lock on | ✅ companion back in front every time |
| Brightness: adaptive setup (mode 1, level 2) and manual level (140) restored after Day / Night / Manual | ✅ |

Bugs found and fixed (each with a test where one can exist):

- **Idle clock wrapped** ("23:0" / "2") on 360 dp: it is 150 sp text; now scaled to one line (`test/glance_page_test.dart`).
- **Weather card unreadable on a phone**, in the full page and in the docked overlay: four forecast days beside the text left it no
  width; below 560 dp the forecast now goes under the text (`test/voice_cards_layout_test.dart`; the overlay is checked on the device only).
- **Shade could be pulled open under the accessibility guard.** The shade sends no window-state event while it is dragged and the
  global dismiss action returns `false` on this phone. The guard now watches System UI content changes, recognises an open shade by a
  System UI window taller than a quarter of the screen (never on the lock screen), and swipes it shut with an injected gesture
  (`canPerformGestures`); Back and Home are fallbacks. A first version also fired on the lock screen and made the PIN pad unusable.
  An app that is not device owner can only *react*: the lock-task route stays the complete fix.
- **Fast repeated Back left the Pixel launcher in front** (the second launcher event fell inside the bounce debounce and no
  event followed): a bounce is now verified 700 ms later and repeated.
- **Brightness `manual` left the phone dark** after Day/Night: the controller now restores the system mode and level it found.
- Review fixes found by reading the code: a tablet's event data could replace `device_id` / `event` on the bus, a socket closing
  mid-write leaked a raw error and a pending entry, reloading the integration duplicated mirrored timers in the timer manager, and
  malformed JSON frames from either side could raise (`tests/test_device.py`, `test/sidecar_client_test.dart`).

Lab and tooling notes: the phone's screen timeout (30 s) puts it back on the lock screen between steps, so tests need the timeout raised
(and restored); `dumpsys window | grep mCurrentFocus` says `NotificationShade` even when nothing is pulled down on Android 17, so judge
the shade by screenshots; the lab's `internal_url` must be the address the phone reaches (`http://127.0.0.1:8123` with `adb reverse`),
not the emulator's `10.0.2.2`. Not verified: wake word CPU and battery over time, the docked card over other apps (needs the
"draw over other apps" permission, which stayed off), Settings staying blocked after the 30 minute system-update exception, and
anything with real speech (the lab speech-to-text is a fixed phrase).

### Pixel 6: hardening and chaos run (no device owner, accessibility guard only)

Attacks on the locked kiosk, each checked by foreground activity and screenshots over time:

| Attempt | Result |
|---|---|
| Notification shade / quick settings: slow pull (3 s, 6 s), fast pull, from the quick-settings side, `cmd statusbar expand-notifications` / `expand-settings` | ✅ never visible in the captured frames |
| Recents key | ✅ the overview flashes for about a second, then the companion is back; it cannot stay |
| Long-press Home, assistant key | ✅ nothing / assistant pushed back to the companion |
| Back pressed 10× at 0.1–0.8 s intervals (the way someone back-swipes out of the app) | ✅ companion in front every time |
| Force-stop the companion app | ✅ relaunched by the guard within seconds |
| Settings (intent) | ✅ refused |
| Long press on power: power menu (Emergency, Lockdown, Power off, Restart) | ❌ **stayed open** → fixed: a System UI dialog is now closed with Back, checked three times |
| Lock screen with the kiosk lock on | ✅ not touched by the guard |

Not preventable without device owner, and written down for the tablet trial: a hardware power-off (hold power + volume), safe mode on
boot, and the first seconds of a reboot before the app starts. The lock-task mode of a device owner is the answer to all three.

Chaos: a 50 s timer started from HA, **Home Assistant stopped** → the timer ran and rang on the phone by itself ("Time's up"), was
dismissed on the phone, and after HA came back the sidecar was connected with correct state 23 s after the start of Home Assistant's own boot
(timers 0, no ringing flags). The lab's REST token (1 day) had expired meanwhile: a 401 from the lab is not a sidecar problem.

CI (found and fixed on 2026-10-11): `hassfest` and the HACS validation had been failing since the integration was added
(device filter in `services.yaml`, `<...>` in strings, missing `assist_pipeline` / `intent` dependencies); Android lint found a crash on
Android 8.0 (API 27 calls with minSdk 26) and a missing coarse-location permission. See docs/CI.md.

Soak (Pixel 6, 2026-10-11, 54 clean minutes, screen on, wake word + camera presence + kiosk lock + HA connected): sidecar CPU 57–61 %
of one core (flat), memory 251–272 MB (garbage-collection wobble, no trend), battery 85 → 73 % (about 14 %/h, mostly the screen),
28 → 32.4 °C, **no wake-word activation and no guard trigger** in a quiet room. Where the CPU goes (top -H): the wake word's audio thread
about a third of a core plus TFLite's helper pool, camera presence about 10 %. Limiting the TFLite threads of the embedding and word
models to 2 measured 47 % instead of 58 % (same results: threads do not change the maths; wake-word *detection* was not re-run on the
device after that change because the phone ran out of battery: re-check with your own voice).
The Mac slept for 18 minutes once: the phone kept running, and the tablet reconnected 29 s after the tunnel returned (backoff 1…30 s).
Release build (`flutter build apk --release`, R8, signed with the debug key): starts and renders on the emulator, the wake word engine loads
(TFLite XNNPACK delegate) and listens; it was not yet run on the phone.

### Pixel 6 full regression after a reboot (2026-10-11, debug build with the owner-removal feature, lab HA restarted)

The phone came back on its own and reconnected to the lab (the "broken" state was only the lab Home Assistant being down).

| Area | Result |
|---|---|
| **`dpm set-device-owner` with the Google account still bound** | ❌ rejected by Android, as expected: `IllegalStateException: Not allowed to set the device owner because there are already some accounts on the device.` Nothing changed (no owner). Removing the account is what decides whether it can work on a set-up device. |
| Timer: 15 s, rings, dismissed from the phone | ✅ |
| Lock attacks (slow / fast / quick-settings shade pull, Recents, long-press Home, long-press power, 10× Back at 0.2 s, force-stop the companion, Settings, Maps) | ✅ companion in front every time; **Settings stays blocked** now that the update exception has expired (an item that was open before) |
| HA's menu button (top left) while locked | ✅ opens |
| PIN corner (bottom left): five taps → PIN pad, wrong PIN counted, right PIN unlocks, relock from HA | ✅ |
| Voice turn with the docked card, answer, follow-up wait; result card (weather with forecast) | ✅ |
| Voice volume 2 → 5 while listening → back to 2 | ✅ after a fix: **a turn cancelled from Home Assistant (`cancel_listening`) left the volume raised** (the conversation flag stayed on, so the restore never ran); `test/voice_controller_test.dart` covers it |
| Brightness: adaptive setup restored after Day → Manual | ✅ |
| Idle clock screen, touch dismisses it | ✅ |
| Camera presence running, alarm set / cancel, 103 entities, no errors in the HA log | ✅ |

Suites: 46 Python, 19 JS, 119 Dart, analyzer clean, Android lint 0 errors, Gradle unit tests pass.

