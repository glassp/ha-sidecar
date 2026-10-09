# Wire protocol (v1)

Transport: WebSocket, text frames with JSON, tablet → `GET {ha_url}/api/ha_sidecar/ws` (use `wss://` behind TLS).
HA sends WebSocket pings every 30 s (aiohttp `heartbeat`).

## Handshake

```
app → HA   {"type":"hello","protocol":1,"token":"<pairing token>","device":{"manufacturer","model","android","sdk"}}
HA  → app  {"type":"hello_ok","device_id":"<uuid>","protocol":1}
           or {"type":"auth_failed"} (socket closed; app stops retrying until re-paired)
           or {"type":"error","error":"unsupported_protocol"}
```
`hello` must arrive within 10 s. A new connection for the same token replaces the old one.

## App → HA

```
{"type":"state","state":{...}}                       partial or full; merged into HA's cached state
{"type":"event","event":"alarm_ringing","data":{}}   re-fired on the HA bus as `ha_sidecar_event`
{"type":"result","id":7,"success":true,"data":{}}    answer to a command
{"type":"result","id":7,"success":false,"error":"pin_required","message":"…"}
```

State keys: `mode` (`device_owner|accessibility|none`), `lockdown`, `has_pin`, `keep_screen_on`, `screen_on`,
`brightness`, `target_package`, `allowlist`, `foreground_app`, `battery_level`, `charging`, `android_release`, `sdk`,
`security_patch`, `build`, `manufacturer`, `model`, `device_owner`, `accessibility_enabled`, `overlay_granted`,
`write_settings_granted`, `pending_update` (object or null), `next_alarm` (epoch ms), `alarm_ringing`.

Events: `alarm_ringing`, `alarm_stopped` (`reason`: dismissed/snoozed/timeout), `system_update_pending`,
`system_update_install_error`, `update_automation_started`, `update_automation_step`, `update_automation_finished` (`reason`: idle) (`label` = button tapped), `lockdown_disabled_by_pin`.

## HA → app

```
{"type":"command","id":7,"command":"set_lockdown","data":{"enabled":true}}
```
| Command | Data | Notes |
|---|---|---|
| `set_lockdown` | `enabled` | enabling fails with `pin_required` / `no_enforcement_available` |
| `set_allowlist` | `packages[]` | |
| `set_kiosk_launcher` | `enabled` | sidecar acts as home app (boot start + crash recovery); device owner forces it, otherwise the user picks it in Android settings |
| `set_target_package` | `package` | default: HA companion (full or minimal) |
| `launch_app` | `package`, optional `path` | `path` deep-links the HA app via `homeassistant://navigate/<path>` |
| `bring_to_front` | optional `path` | foregrounds the HA app by intent; never restarts it |
| `screen` | `on` | off needs device owner or accessibility |
| `set_brightness` | `level` 0-255 | needs *modify system settings* |
| `set_keep_screen_on` | `enabled` | |
| `set_alarm` | `alarm{id,hour,minute,days[1-7],label,enabled,snooze_minutes}` | empty `days` = once |
| `cancel_alarm` / `stop_alarm` / `snooze_alarm` / `get_alarms` | | |
| `open_system_update` | | opens the screen only; temporarily allowlists Settings |
| `run_system_update` | | opens the screen and taps through it via the accessibility service (`needs_accessibility` otherwise) |
| `install_system_update` | `uri` | device owner, A/B devices, caller supplies the OTA zip |
| `reboot` | | device owner |

Unknown commands → `unknown_command`. Commands time out after 20 s on the HA side.

## Security notes

- The token is the only credential; treat it like a password. It is shown once in the config flow and stored in the config entry.
- Remote *disable* of lockdown is intentionally possible (HA is the admin). Remote *enable* requires a PIN on the device so
  nobody gets locked into a tablet they can't leave.
- TODO: QR pairing, token rotation, per-command audit log.
