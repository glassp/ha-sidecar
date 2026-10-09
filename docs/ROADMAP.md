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

### 2. Smart-display surface
- Dart "idle screen" shown when the dashboard is idle: clock, next alarm, weather/camera/photo slideshow.
- Idle detection: no touch for N s (needs a transparent touch-observer overlay or accessibility events).
- Dimming curve + presence wake (HA `binary_sensor` → `screen` command already works).
- Screenshot + battery/uptime sensors.

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
