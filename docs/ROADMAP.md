# Roadmap

Kiosk Satellite (KS) is the closest existing project. Its license (CC BY-NC-ND 4.0) forbids derivatives, so this table is
based on its **public docs only**; everything here is implemented independently. Do not read or port its source.

| KS feature (from its docs) | Here |
|---|---|
| PIN-protected kiosk, lockdown, device-owner lock task, accessibility "system UI guard" | ✅ scaffolded (phase 1) |
| Home-Assistant-facing entities (switches, sensors, buttons) over ESPHome native API | ✅ own WebSocket + HA integration instead of ESPHome. works through reverse proxies; discovery is mDNS pairing (phase 2.7, [PAIRING.md](PAIRING.md)) |
| Alarms (next alarm, ringing, stop, snooze) | ✅ native `setAlarmClock`; plus remote mute / skip next / enable, labeled timers and stopwatches (phase 2.3) |
| Remote screen on/off, brightness, keep screen on | ✅ all brightness settings are entities (percentage and raw), night mode actions |
| Reboot (device owner) | ✅ |
| OS update entity | ✅ (detection: device owner only) - KS lists an app-update entity, ours is the OS |
| Foreground app, battery, charging, Android version sensors | ✅ partial |
| Voice Satellite (wake word, Assist, TTS, timers) | ⏳ phase 3 (the timer engine it needs exists since phase 2.3) |
| Screensaver (clock, photos, Immich, "at a glance") | ✅ at-a-glance (clock, next alarm, timers, HA values) or an own glance dashboard; ⏳ photos / Immich |
| Screensaver triggers: motion/face/proximity via camera | ⏳ phase 2/4 |
| Media player / DLNA / Music Assistant | ⏳ phase 4 (optional) |
| Intercom between tablets | ⏳ phase 4 (optional) |
| Camera streams on demand | ❌ companion app / HA dashboards cover this |
| Screenshots, camera snapshot entities | ⏳ phase 2 |
| Remote admin API/UI, fleet management | ❌ HA is the admin plane |
| Plugin system, JS API | ❌ non-goal |
| Own dashboard WebView | ❌ non-goal: the official companion app does this |

## Phases

Status as of 2026-10-09. Everything marked done was built and exercised on an Android 15 emulator against a real Home
Assistant (see [TESTING.md](TESTING.md)); nothing has run on a physical tablet yet (checklist at the end).

| Phase | State |
|---|---|
| 1 Kiosk core | done |
| 2 Smart-display surface (brightness, presence, glance, camera, dashboards) | done |
| 2.1 App UI: wizard, search, translations, Flutter-only screens | done |
| 2.3 Timers, stopwatches and remote alarm control | done |
| 2.4 Naming, brightness units, night mode actions | done |
| 2.5 Companion app watchdog | design only |
| 2.7 Discovery, pairing and network-aware connection | done (discovery itself unverified on a real LAN) |
| 3 Voice | not started |
| 4 Optional | not started |

### 1. Kiosk core (done)
Lockdown (device owner lock task, or accessibility fallback), allowlist, on-device PIN with cooldown, home-app role (boot
start, crash recovery), remote enable/disable (needs a PIN and a kiosk dashboard), alarms, OS update signal and trigger,
entities/services, the HACS integration. Sidecar and the Home Assistant companion app run side by side.

### 2. Smart-display surface (brightness, presence, glance, camera: done, see [DISPLAY.md](DISPLAY.md))
Done: time-of-day brightness, idle dim, night light on presence, HA presence/night inputs, camera motion presence (menu),
at-a-glance screen, last-interaction and camera/mic sensors. Still open from the original list: screenshot entity,
ambient-light scaling, glance variants (photos/Immich), face/person detection (needs an ML model), per-hour brightness curve.

Original plan:
- Dart "idle screen" shown when the dashboard is idle: clock, next alarm, weather/camera/photo slideshow.
- Idle detection: no touch for N s (needs a transparent touch-observer overlay or accessibility events).
- Dimming curve + presence wake (HA `binary_sensor` → `screen` command already works).
- Screenshot + battery/uptime sensors.

### 2.1 App UI (done, see [UI.md](UI.md))
First-run setup wizard that explains and guides every permission; Home / Kiosk / Display / Alarms / System tabs; a settings
search over every setting; kiosk dashboard (required) and idle/glance dashboard (optional) taking pasted browser URLs; brand
icons; English and German (`easy_localization`); `beamer` routing; **no native screens**: the PIN pad, ringing alarm and idle
screen are Flutter pages of one activity.

### 2.3 Timers, stopwatches and remote alarm control (done)
Labeled countdowns and count-ups on the tablet (persistent, exact wake-up, survive reboot), shown on the idle screen and in
the app; a finished countdown rings and counts the time it is over until dismissed. Home Assistant can start / pause /
resume / adjust / cancel them (by id or label), gets `timer_*` events, and has sensors (next timer, timers, alarms). Alarms
can be muted (also for a duration, e.g. while away), skipped once, enabled or disabled remotely. Details in
[PROTOCOL.md](PROTOCOL.md).

### 2.4 Naming, brightness units and night mode (done)
Entities are `<domain>.<prefix>_<entity>` with a prefix chosen at setup (Home Assistant forbids `__` in entity ids).
Brightness is a percentage by default in the app (raw 0-255 is a developer option) and every brightness has a
`..._percentage` and a `..._raw` entity. `enter_night_mode` / `exit_night_mode` actions drive the night state from
automations.

### 2.5 Companion app watchdog (frozen / non-responsive HA app) - design, not built

**Problem.** Crashes and kills are already handled (home role: Android returns to the sidecar, which relaunches the HA
app). A *frozen* app is not: it is still "running" so nothing relaunches it. Failure modes:

| # | Failure | Looks like | Handled today |
|---|---|---|---|
| F1 | Cold-start hang (splash forever, never reaches the dashboard) | process alive, UI never changes | no |
| F2 | UI-thread freeze / ANR | touches ignored, system may show "App isn't responding" | no |
| F3 | WebView renderer hang or blank/white page (UI thread alive) | app responds, page is dead or stale | no |
| F4 | Crash / kill / lock-task exit | app gone | yes |

**Spike results (emulator, Android 15, companion 2026.8.4, process frozen with `kill -STOP`):**
- Accessibility tree of a frozen app: retrieval fails with a *null root node* within ~3 s (healthy app: 20 nodes).
  A frozen UI thread (F1/F2) is therefore detectable with a cheap probe from the accessibility service, no screen capture.
- After the first touch the *system* raises the ANR dialog within ~2 s: package `android`, text "Home Assistant isn't
  responding", buttons "Close app" / "Wait". Visible in the accessibility tree, so it can be recognised and answered.
  "Close app" kills the process.
- Kill-from-outside: `pm suspend` (= `setPackagesSuspended`) did **not** kill the stopped process; `pm hide` /
  `setApplicationHidden(true)` did, and `unhide` + relaunch gave a healthy process with data intact. A device owner can
  use `setApplicationHidden(admin, pkg, true/false)`.
- Not covered by any of this: F3 (the UI thread is fine, the page is dead). Needs a content-level signal.

**Detection signals (combine, each with a grace period):**
1. *UI probe* (F1, F2): every 15-30 s while the HA app is foreground, the screen is on and nothing else is running,
   `rootInActiveWindow` of the target; null/empty for N consecutive probes = unresponsive. Cold start: after a launch we
   issued, expect a non-splash tree within `startup_timeout` (default 90 s).
2. *ANR dialog* (F2): accessibility sees package `android` + "isn't responding" naming the HA app.
3. *Visual freeze* (F3, optional, off by default): accessibility screenshot (Android 11+, needs the screenshot capability)
   hashed on a tiny grid; identical for `visual_timeout` while the screen is on and brightness is unchanged.
   Needs a live element on the dashboard (a clock card); otherwise static dashboards false-positive.
4. *HA-side heartbeat* (F2/F3, optional): the integration flags the tablet when a companion-app sensor with a short update
   interval (Fast Always = 1 min) or a heartbeat card has not updated for N minutes, and sends `restart_companion`.
   Slow and needs user setup, but independent of the tablet.
5. *Scheduled restart* (blunt, also fixes stale dashboards): restart the HA app on a schedule in a quiet period.

**Recovery (rate limited):**
- Device owner: `setApplicationHidden(true)` then `false`, then `launchTarget(lockTask + dashboard)`. With lock-task the
  task ends and the home role relaunches it anyway.
- Without device owner: if the ANR dialog is up, tap "Close app" (accessibility); otherwise drive Settings → App info →
  Force stop (same mechanism as the update automation; label-matched, OEM dependent) and relaunch. Last resort: notify HA.
- Policy: never while an alarm rings or the PIN screen is open; skip when the screen is off; max 3 restarts per
  10 minutes with back-off, then stop restarting and raise an HA event instead (a boot loop must not hide a real problem).
  A restart is reported with its reason.

**HA surface.** `binary_sensor` Companion app responsive (problem class), `sensor` Companion restarts (total increasing)
and Last restart reason, `switch` Watchdog, numbers for the probe interval / startup timeout / visual timeout, `select`
action (`restart` | `notify only`), `button` Restart companion app, bus events `companion_unresponsive`,
`companion_restarted`, `companion_restart_gave_up`.

**Evaluation plan (this is why it is a half phase).**
1. Freeze lab on the emulator: `kill -STOP` (F2), a page that blocks the renderer (F3), a launch that never finishes (F1).
   Measure detection latency and false positives on a healthy device over a day (dimming, glance dashboard, screen off).
2. Implement signals 1 and 2 plus the device-owner recovery first; decide on 3-5 from the false-positive data.
3. Tune probe interval vs battery; confirm the accessibility probe does not wake the screen or reset dimming.
4. Real tablet: low memory, slow storage, OEM ANR dialog wording (the dialog text is localized: match by package +
   button roles, not only English text).

### 2.7 Discovery, pairing and network-aware connection (done, see [PAIRING.md](PAIRING.md))
mDNS: the tablet advertises `_ha-sidecar._tcp` while its pairing mode is on, Home Assistant discovers it (zeroconf) and the two
pair with an ECDH handshake: confirm the six-digit number on the tablet, or use IP + the code the tablet shows when discovery is
not available. Home Assistant hands over the connection token and its address(es) encrypted. Also: internal and external address,
home networks (Wi-Fi name, Ethernet, VPN) and a *home network only* option for the persistent connection.
Open: QR pairing, reconfigure/re-pair from Home Assistant, verification on a real network (the emulator cannot bridge multicast).

### 3. Voice
- Integration side: implement `assist_satellite` entity platform (`AssistSatelliteEntity`): `async_announce`,
  `async_set_configuration`, pipeline events; audio over a second binary WebSocket stream or HA's `assist_pipeline/run`.
- App side: push-to-talk first, then on-device wake word behind `WakeWordEngine` (openWakeWord via TFLite, in a
  foreground service of type `microphone`; needs `RECORD_AUDIO`), TTS playback with audio focus + ducking, listening
  UI overlay on top of the companion app (accessibility overlay) showing Assist responses/cards.
- **Answer UI** (modelled on what KS's docs describe, own design): a native overlay, *not* inside the dashboard WebView,
  so it stays smooth. Docked conversation bubble at the bottom with the dashboard still visible and usable underneath;
  reactive activity bar following mic level / TTS; transcript and answer toggles; auto-dismiss timers; double-tap to
  end a turn; result cards (weather, image, media) from the conversation log; draggable timer pills; error notices that
  name the failing stage (mic, wake word, connection, TTS, pipeline). Implementation: accessibility overlay window hosting
  a Flutter surface (second `FlutterEngine`/`FlutterView` in a service) or plain native views for v1; skins as themes.
- Timers: the native timer engine and alarm audio path exist (phase 2.3); voice only has to create timers through them and mirror HA `timer`s.

### 4. Optional
Media player entity, intercom, camera-based motion/presence, Bluetooth proxy (ESPHome BT proxy protocol), iOS/desktop ports
(implement `KioskPlatform`; lockdown on iOS = Guided Access, not scriptable).

## Open design questions
- Nightly "reload/restart HA app" job to mitigate stale dashboards (DO: reboot; non-DO: relaunch).
- Pairing UX: QR code on the tablet (zeroconf advertisement and code pairing are done, see PAIRING.md).
- Token rotation / re-pair flow in the integration (reconfigure step); long-term identity pinning after pairing.
- Entity prefix is fixed at setup; a rename flow would need to migrate registry ids.
- Dashboard buttons / blueprints for timers (Batch 1 style presets) and a voice front end for them.
- Whether to allow `clearDeviceOwnerApp` from the app behind the PIN (currently only factory reset removes ownership).
- Play Store distribution is doubtful (accessibility + device-owner use, `USE_FULL_SCREEN_INTENT`); plan on F-Droid/GitHub APKs.

## First device test checklist
Steps 2-5 (partly 7) were run on an emulator, see [TESTING.md](TESTING.md); all of it still needs a physical tablet.
1. Debug APK installs; pairing works (**mDNS discovery on the real LAN**, then the manual code route across VLANs); entities appear and go unavailable when the app is killed.
2. Accessibility mode: lockdown on → Home/Recents/shade/Settings all bounce to the HA app; keyboard still works in HA; HA app's own launcher mode doesn't fight the guard.
3. Device-owner mode: `dpm set-device-owner` succeeds; lock task starts for the HA app via `setLockTaskEnabled`; status bar gone; hot corner overlay still receives taps (**most likely failure point**); PIN disables.
4. Remote `launch_app` / bounce while the HA app is in front (background-activity-start restriction).
5. Alarm: rings with screen off, over lock screen and over lockdown; snooze/dismiss; survives reboot; shows as system next alarm.
6. `onSystemUpdatePending` arrives (needs a real OTA); stale-fingerprint clearing after update.
7. Process death: kill the app; lockdown (accessibility service restarts by system, DO policy persists) and alarms still work.
8. Android 14/15/16/17 foreground-service-type and full-screen-intent permission behavior.
9. Timers: a countdown rings on time with the screen off and in Doze, survives a reboot (a timer that ended while off rings at boot), count-ups keep counting; muted alarms stay silent and keep their schedule.
10. Network: home-Wi-Fi detection (needs the location permission and a real SSID), VPN-as-home, Ethernet, switching internal/external address while moving between networks, *home network only* idling away from home.
