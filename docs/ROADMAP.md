# Roadmap

Kiosk Satellite (KS) is the closest existing project. Its license (CC BY-NC-ND 4.0) forbids derivatives, so this table is
based on its **public docs only**; everything here is implemented independently. Do not read or port its source.

| KS feature (from its docs) | Here |
|---|---|
| PIN-protected kiosk, lockdown, device-owner lock task, accessibility "system UI guard" | ✅ scaffolded (phase 1) |
| Home-Assistant-facing entities (switches, sensors, buttons) over ESPHome native API | ✅ own WebSocket + HA integration instead of ESPHome. Trade-off: no zero-config discovery, but no key exchange/mDNS/BLE-permission dance and works through reverse proxies |
| Alarms (next alarm, ringing, stop, snooze) | ✅ scaffolded, native `setAlarmClock` |
| Remote screen on/off, brightness, keep screen on | ✅ scaffolded |
| Reboot (device owner) | ✅ |
| OS update entity | ✅ (detection: device owner only) - KS lists an app-update entity, ours is the OS |
| Foreground app, battery, charging, Android version sensors | ✅ partial |
| Voice Satellite (wake word, Assist, TTS, timers) | ⏳ phase 3 |
| Screensaver (clock, photos, Immich, "at a glance") | ⏳ phase 2 |
| Screensaver triggers: motion/face/proximity via camera | ⏳ phase 2/4 |
| Media player / DLNA / Music Assistant | ⏳ phase 4 (optional) |
| Intercom between tablets | ⏳ phase 4 (optional) |
| Camera streams on demand | ❌ companion app / HA dashboards cover this |
| Screenshots, camera snapshot entities | ⏳ phase 2 |
| Remote admin API/UI, fleet management | ❌ HA is the admin plane |
| Plugin system, JS API | ❌ non-goal |
| Own dashboard WebView | ❌ non-goal: the official companion app does this |

## Phases

### 1. Kiosk core (this scaffold)
Lockdown (DO + accessibility), allowlist, PIN, alarms, OS update signal, entities/services.

### 2. Smart-display surface (brightness, presence, glance, camera: done, see [DISPLAY.md](DISPLAY.md))
Done: time-of-day brightness, idle dim, night light on presence, HA presence/night inputs, camera motion presence (menu),
at-a-glance screen, last-interaction and camera/mic sensors. Still open from the original list: screenshot entity,
ambient-light scaling, glance variants (photos/Immich), face/person detection (needs an ML model), per-hour brightness curve.

Original plan:
- Dart "idle screen" shown when the dashboard is idle: clock, next alarm, weather/camera/photo slideshow.
- Idle detection: no touch for N s (needs a transparent touch-observer overlay or accessibility events).
- Dimming curve + presence wake (HA `binary_sensor` → `screen` command already works).
- Screenshot + battery/uptime sensors.

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
- Timers: HA `timer`s mirrored as native countdown notifications; reuse the alarm audio path.

### 4. Optional
Media player entity, intercom, camera-based motion/presence, Bluetooth proxy (ESPHome BT proxy protocol), iOS/desktop ports
(implement `KioskPlatform`; lockdown on iOS = Guided Access, not scriptable).

## Open design questions
- Nightly "reload/restart HA app" job to mitigate stale dashboards (DO: reboot; non-DO: relaunch).
- Pairing UX: QR code from config flow; zeroconf advertisement from the app.
- Token rotation / re-pair flow in the integration (reconfigure step).
- Whether to allow `clearDeviceOwnerApp` from the app behind the PIN (currently only factory reset removes ownership).
- Play Store distribution is doubtful (accessibility + device-owner use, `USE_FULL_SCREEN_INTENT`); plan on F-Droid/GitHub APKs.

## First device test checklist
Steps 2-5 (partly 7) were run on an emulator, see [TESTING.md](TESTING.md); all of it still needs a physical tablet.
1. Debug APK installs; pairing works; entities appear and go unavailable when the app is killed.
2. Accessibility mode: lockdown on → Home/Recents/shade/Settings all bounce to the HA app; keyboard still works in HA; HA app's own launcher mode doesn't fight the guard.
3. Device-owner mode: `dpm set-device-owner` succeeds; lock task starts for the HA app via `setLockTaskEnabled`; status bar gone; hot corner overlay still receives taps (**most likely failure point**); PIN disables.
4. Remote `launch_app` / bounce while the HA app is in front (background-activity-start restriction).
5. Alarm: rings with screen off, over lock screen and over lockdown; snooze/dismiss; survives reboot; shows as system next alarm.
6. `onSystemUpdatePending` arrives (needs a real OTA); stale-fingerprint clearing after update.
7. Process death: kill the app; lockdown (accessibility service restarts by system, DO policy persists) and alarms still work.
8. Android 14/15/16/17 foreground-service-type and full-screen-intent permission behavior.
