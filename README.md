# HA Sidecar

Turn any Android tablet into a Home Assistant wall display - using the **official Home Assistant
companion app** for the dashboard and a small **sidecar app** for everything the companion app
(deliberately) does not do:

| Sidecar feature | How |
|---|---|
| Kiosk lockdown (no shade, no recents, no home) | **Device owner / lock-task mode** if provisioned, otherwise an **accessibility service** fallback |
| App allowlist | Anything not allowlisted is blocked (lock task) or bounced back to the HA app (accessibility) |
| On-device PIN exit | Tap the top-left corner 5x, enter PIN. Works without the Flutter engine running |
| Foreground the HA app | Intent-based (`bring_to_front`, optional `homeassistant://navigate/` deep link), never restarts the app |
| Remote enable/disable | HA switch `Kiosk lockdown` (remote *enable* needs a PIN to exist on the device) |
| Native alarms | `AlarmManager.setAlarmClock` - shows up as the system "next alarm", rings over lock screen/kiosk, snooze/dismiss, HA services + entities |
| OS update | `update` entity; detection via the device-owner `onSystemUpdatePending` callback; "install" taps through the system update screen via the accessibility service |
| Screen control, brightness, reboot | Buttons/numbers in HA |
| Brightness | Day / idle-dim / night / **night light on presence**, fading, all settable as entities ([docs/DISPLAY.md](docs/DISPLAY.md)) |
| Presence | HA presence entities and/or an optional on-device camera motion detector (menu in the app) |
| At a glance | Clock, next alarm and chosen HA values after idle; dismissed by touch or presence |
| Extra sensors | last interaction, camera/mic in use, blocked apps, PIN failures (the companion app's own sensors are not duplicated) |
| Theme | `App theme` select: system / light / dark / dark at night |
| Voice assistant (planned) | Assist satellite, see [docs/ROADMAP.md](docs/ROADMAP.md) |

## The app

First start opens a **setup wizard** (connect, purpose, companion app, kiosk dashboard, PIN, protection, permissions with a
grant button per item, start-up, brightness). After that the app has five tabs: **Home** (status, one-tap lock, what still
needs attention), **Kiosk** (dashboards, lock, PIN, allowed apps, start-up), **Display** (brightness, night light, presence,
camera), **Alarms**, **System** (connection, permissions, updates, theme, language). A global **search** finds any setting.
English and German; light/dark theme. See [docs/UI.md](docs/UI.md).

## Timers, stopwatches and remote alarm control

Labeled countdowns ("Batch 1") and count-ups ("Treadmill") run on the tablet and show on the idle screen. A finished
countdown rings and keeps counting how long it has been over until dismissed. Home Assistant gets
`ha_sidecar_event` events (`timer_finished`, `timer_started`, ...) and can drive everything:

```yaml
action: ha_sidecar.start_timer
data: { duration: "00:25:00", label: "Batch 1" }
target: { device_id: <tablet> }
```

Services: `start_timer`, `start_stopwatch`, `pause_timer`, `resume_timer`, `cancel_timer`, `adjust_timer` (address a timer
by `timer_id` or the `label` it was started with), and for alarms `set_alarm`, `set_alarm_enabled`, `skip_next_alarm`,
`mute_alarms` (optionally for a duration, e.g. while away), `unmute_alarms`, `stop_alarm`, `snooze_alarm`. Entities:
`switch.<tablet>_alarms_muted`, `sensor.<tablet>_next_timer` (timestamp, a live countdown on dashboards),
`sensor.<tablet>_timers` and `sensor.<tablet>_alarms` (counts, details as attributes), `binary_sensor.<tablet>_timer_ringing`.

## Repository layout

```
app/                         Flutter app (dev.glassp.ha_sidecar), Android implementation in Kotlin
custom_components/ha_sidecar HACS integration (domain: ha_sidecar)
docs/                        architecture, wire protocol, provisioning, roadmap
hacs.json                    HACS metadata
```

## How it behaves on the tablet

The sidecar runs in the background (foreground service + a headless Flutter engine that holds the HA connection); you
only open its UI for setup. With **Act as home app** on it is also the tablet's home app: Android starts it at boot and
whenever no app is left (HA app crashed or was killed, lock-task ended), and it immediately puts the HA companion app
back in front (inside lock-task when lockdown is on). On a device owner it makes itself the home app without a prompt;
otherwise you pick "HA Sidecar" as the default home app once in Android settings. You do **not** need to set the HA
companion app as the launcher.

## Quick start

1. **HA:** install the integration (HACS custom repository, category *Integration*), restart,
   *Settings → Devices & services → Add → HA Sidecar*, name the tablet, copy the token.
2. **Tablet:** `cd app && flutter build apk` and install; open the app, enter HA URL + token.
3. In the app: set the **kiosk dashboard** (paste the address of the HA dashboard from your browser) and a PIN, grant the listed permissions, then either
   - provision as device owner ([docs/PROVISIONING.md](docs/PROVISIONING.md)) - recommended, or
   - enable the accessibility guard (weaker). Enabling it is also recommended with device owner (foreground reporting).
4. Install and sign in to the HA companion app (enable its fullscreen setting; do not make it the launcher).
5. Turn on **Act as home app**, then toggle **Kiosk lockdown**.

## Status

Phase 1 works end to end on an **Android 15 tablet emulator against Home Assistant 2026.10.0** with the real companion
app (device-owner lockdown, accessibility fallback, PIN, alarms, remote control, reboot recovery); see
[docs/TESTING.md](docs/TESTING.md) for what was and was not verified. **Not yet tried on a physical tablet**, and
OS-update *detection* and the automated update taps need a real pending OTA to verify.

License: Apache-2.0.
