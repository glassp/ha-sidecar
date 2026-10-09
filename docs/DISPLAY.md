# Display, presence and glance

Everything here runs **on the tablet** (works when HA is unreachable); HA only supplies inputs and settings.
All settings are entities of the tablet's device (category *Configuration*), so automations, scripts, dashboards and
helpers can drive them. The same settings are in the app under *Display & presence* and *Camera & presence*.

## Brightness logic

| Situation | Brightness |
|---|---|
| Day, touched recently or someone near | `Day brightness` |
| Day, idle for `Dim after`, nobody near (and `Dim when idle` on) | `Day idle brightness` |
| Night, nobody near | `Night brightness` |
| Night, someone near (and `Night light` on) | `Night light brightness` (enough to see the floor) |
| Night, touched | `Night brightness after touch` for `Night touch hold time` |

Changes fade over `Brightness fade time`. "Someone near" = a presence entity is on, or the presence camera saw
movement, each kept for `Presence hold time` after the last detection.

`Brightness mode` (select): `manual` (default, the sidecar never touches brightness), `auto` (follows night), `day`,
`night` (force a period). In `auto`, night is: the *night entity* if you set one in the integration options,
otherwise the schedule `Night starts` / `Night ends`. Needs the "Modify system settings" permission.

## Inputs from Home Assistant (integration options)

Settings → Devices & services → HA Sidecar → Configure:
- **Presence entities**: any binary_sensor / input_boolean / switch (mmWave, PIR, a helper you set from automations).
  Any of them on = someone is near.
- **Night entity**: `sun.sun` (night = below horizon) or any on/off entity / input_boolean (on = night). Empty = schedule.
- **Glance entities**: up to 9 entities shown on the glance screen (units and timestamps are formatted).

To drive a setting from a helper, use a normal automation, e.g. `input_boolean.guest_night_light` → turn the
`Night light` switch on/off, or `input_select.house_mode` → set `Brightness mode`.

## Presence camera (off by default)

Motion detection by frame differencing on a 32×24 luminance grid, 1-10 fps, in memory only: nothing is stored or sent.
A "Presence camera active" notification is shown while it runs. Sensitivity, frame rate and front/back camera are
settings. A device owner grants the camera permission silently; otherwise the app asks once (*Camera & presence*).
Android 14+ only lets camera foreground services start while the app has a visible window; the sidecar's touch-watcher
overlay counts, and a failure is reported in `Presence camera error` instead of crashing.

## Dashboards

Two text settings (entities `Kiosk dashboard` / `Glance dashboard`, and fields under *Display & presence → Dashboards*):

- **Kiosk dashboard** (required before lockdown can be enabled): opened on boot, on Home, after a crash and when lockdown
  starts. Plain bounces back from other apps keep the page you were on.
- **Glance dashboard** (optional): an ordinary Home Assistant dashboard shown when idle instead of the built-in clock screen.
  Build it in HA's editor with any cards (weather with animation, temperatures per floor, camera / WebRTC cards, ...).
  A touch or presence navigates back to the kiosk dashboard. Needs a kiosk dashboard to return to.

Paste the address straight from the browser. Only the path is kept:

| You paste | Stored |
|---|---|
| `https://home.glassp.dev/lovelace/wall-panel` | `lovelace/wall-panel` |
| `/dashboard-kitchen/0?kiosk` | `dashboard-kitchen/0?kiosk` |
| `homeassistant://navigate/lovelace/default` | `lovelace/default` |
| `https://home.glassp.dev/` (no dashboard) | rejected |

The sidecar opens it with the companion app's deep link `homeassistant://navigate/<path>?server=default`, so the companion
app does the login. If the pasted host differs from the paired HA, the app tells you only the path is used.
Dashboards with animations or live cameras draw more power than the clock screen; the idle brightness still applies.

## At-a-glance screen (off by default)

Enable it with `At-a-glance screen`. After `Glance screen after` without touch or presence it shows either your glance
dashboard (above) or, if none is set, a native black screen with clock, date, next alarm and the glance entities. A touch or detected presence dismisses it (and restarts the idle timer, so it does not pop straight back).
It does not hold the screen on: use `Keep screen on` (or the system timeout).

## Other new entities

`Last interaction`, `Presence`, `Camera motion`, `Night`, `Camera in use`, `Microphone in use`, `Last blocked app`,
`Blocked app launches`, `PIN failures`; buttons `Show/Hide glance screen`; select `App theme`
(`system | light | dark | night`). Bus events: `app_blocked`, `pin_failed`, `guard_disabled`, `device_admin_disabled`.
