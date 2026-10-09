# Test log and how to reproduce

Last full run: 2026-10-09, emulator `ha_sidecar_tablet` (Android 15 / API 35 google_apis arm64, tablet 2560x1800)
+ Home Assistant Core 2026.10.0 (venv, Python 3.14) + HA companion app 2026.8.4 (`app-minimal-release.apk`).
No physical device yet.

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

### Dashboard beacon card (unit level only)

9 Node tests run the card against a stubbed page (ping on start and interval, no ping when nothing is drawn or the page is hidden,
unknown tablet, escaping, leave notice on navigation, leave notice and listener cleanup on unmount); 12 Python tests cover the
tracker (no verdict without a first ping, stale after the limit, paused while not watching, silence counted from when watching
resumed, inactive is not stale, navigate-then-restart ladder, restart rate limit). `heal_dashboard` and the Python integration
code compile; **nothing ran against a real Home Assistant, the companion app or the dashboard editor yet** (the test Home
Assistant was removed; re-creating it needs a ~1 GB download).

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
