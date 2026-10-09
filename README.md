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
| Voice assistant (planned) | Assist satellite, see [docs/ROADMAP.md](docs/ROADMAP.md) |

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
3. In the app: set a PIN, grant the listed permissions, then either
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
