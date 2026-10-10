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
| Voice assistant (push-to-talk) | Assist satellite entity: talk from the app or start a turn from Home Assistant (`ha_sidecar.listen`), the answer is shown and spoken; announcements play on the tablet. Optional on-device wake word with 21 phrases to choose from, several at once (Alexa, Hey Jarvis, Jarvis, Computer, OK Nabu, ...; the models are downloaded on the tablet, which you manage in a dialog), see [docs/VOICE.md](docs/VOICE.md) |

## The app

First start opens a **setup wizard** (connect, purpose, companion app, kiosk dashboard, PIN, protection, permissions with a
grant button per item, start-up, brightness). After that the app has five tabs: **Home** (status, one-tap lock, what still
needs attention), **Kiosk** (dashboards, lock, PIN, allowed apps, start-up), **Display** (brightness, night light, presence,
camera), **Alarms**, **System** (connection, permissions, updates, theme, language). A global **search** finds any setting.
English and German; light/dark theme. See [docs/UI.md](docs/UI.md).

## Naming

You pair a tablet from the app (System → Pair with Home Assistant, or the setup wizard): it advertises itself over mDNS, Home
Assistant lists it as a discovered device, you press Configure, choose the device name and an
**entity prefix** (for example `wallpanel`). Every entity is then `<domain>.<prefix>_<entity>`: `sensor.wallpanel_timers`,
`number.wallpanel_night_brightness`, so several tablets never collide. (Home Assistant itself forbids a double underscore in
entity ids, so a single underscore separates prefix and name.) The prefix is fixed once created; the name can be renamed.

Connection: the tablet knows an internal and an external Home Assistant address and picks by network (home Wi-Fi, Ethernet,
VPN); the persistent connection can be limited to the home network. Details in [docs/PAIRING.md](docs/PAIRING.md).

Brightness is a percentage in the app by default (raw Android values 0-255 are an opt-in under System > Developer
options). In Home Assistant every brightness has two entities, `..._brightness_percentage` (0-100) and
`..._brightness_raw` (0-255), for example `number.wallpanel_night_brightness_percentage` and
`number.wallpanel_night_brightness_raw`; both change the same setting. Night mode can be driven from automations with the
`ha_sidecar.enter_night_mode` and `ha_sidecar.exit_night_mode` actions (the latter can also hand control back to the
night start/end times).

## Companion app watchdog

Optional (*Kiosk → Watchdog*, needs the accessibility service). While the Home Assistant app is in front the sidecar checks
every few seconds that it still answers (it only counts the app's screen elements, never reads content). If the app freezes,
Android shows "isn't responding", or a fresh start never reaches its screen, the sidecar closes and relaunches it (device
owner: hide + unhide; otherwise via the dialog's "Close app"), at most three times in ten minutes, and tells Home Assistant
(`companion_unresponsive` / `companion_restarted` / `companion_restart_gave_up` events, a *Companion app responsive* sensor,
a restart counter and a *Restart companion app* button). See the 2.5 section of [docs/ROADMAP.md](docs/ROADMAP.md).

## Dashboard beacon card (frozen page detection)

The watchdog above sees a frozen *app*; a frozen or dead *page* inside a healthy app needs the page's help. Add the card
**HA Sidecar beacon** (served by the integration, pick the tablet in the editor) to the dashboard the tablet shows:

```yaml
type: custom:ha-sidecar-beacon-card
tablet: wallpanel      # the entity prefix of the tablet
interval: 30           # optional: seconds between pings (5-300)
compact: false         # optional: hide the status line
```

While the card is on screen it pings Home Assistant every 30 s over the page's own connection (and does not ping when nothing is
being drawn). It tells Home Assistant when it leaves (another dashboard, a view without the card, a reload), so leaving is never
mistaken for a freeze. A dashboard shows only the cards of the view on screen, so put the card on every view the tablet can be
on (or keep the kiosk dashboard to one view). Entities: *Dashboard responsive* (on / off / unknown while the card is not on screen)
and *Dashboard last beacon*.

Silence alone never restarts anything. With *Restart the companion app when the beacon goes silent* switched on in the
integration's options (off by default), a beacon that stops **without** saying goodbye is handled in steps, only while the screen
is on, the app is in front and the tablet is connected: (1) the tablet is sent to the kiosk dashboard with a navigate intent, which
fixes a wrong page and often a stuck one; (2) if no ping returns within 90 s, the companion app is closed and reopened through
the watchdog (same limit of three restarts per ten minutes). Events: `dashboard_unresponsive`, `dashboard_navigate_attempt`,
`dashboard_recovered`.

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
   *Settings → Devices & services*; after pairing starts on the tablet it shows up as discovered. (No discovery? *Add → HA Sidecar*
   and enter the tablet's address and the code it shows.) See [docs/PAIRING.md](docs/PAIRING.md).
2. **Tablet:** `cd app && flutter build apk` and install; open the app and press *Pair with Home Assistant*, then confirm the
   six-digit number on both screens.
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

License: Apache-2.0. The optional wake word uses the openWakeWord models, which are licensed CC BY-NC-SA 4.0 (non-commercial) and are therefore not part of this repository or the app: they are downloaded from the openWakeWord release by the tablet, on request. See [docs/VOICE.md](docs/VOICE.md).
