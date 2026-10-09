# Wire protocol (v1)

Transport: WebSocket, text frames with JSON, tablet → `GET {ha_url}/api/ha_sidecar/ws` (use `wss://` behind TLS).
HA sends WebSocket pings every 30 s (aiohttp `heartbeat`).

Pairing (how the token and address get onto the tablet) is a separate HTTP handshake, see [PAIRING.md](PAIRING.md).

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

Additional state keys: `cfg{...}`, `is_night`, `presence`, `camera_motion`, `camera_active`, `camera_error`,
`camera_permission`, `target_brightness`, `display_error`, `last_interaction` (epoch ms), `camera_in_use`, `mic_in_use`,
`last_blocked_app`, `blocked_count`, `pin_failures`, `glance_showing`.

Events: `app_blocked`, `pin_failed`, `guard_disabled`, `device_admin_disabled`, `alarm_ringing`, `alarm_stopped` (`reason`: dismissed/snoozed/timeout), `system_update_pending`,
`system_update_install_error`, `update_automation_started`, `update_automation_step`, `update_automation_finished` (`reason`: idle) (`label` = button tapped), `lockdown_disabled_by_pin`.

Voice (see [VOICE.md](VOICE.md)): `{"type":"voice","action":"start|audio|stop|cancel|played","session":"<tablet's id>",...}`;
`start` may carry `wake_word`, `audio` carries `data` (base64, 16 kHz mono PCM16, 100 ms per frame).

## HA → app

```
{"type":"command","id":7,"command":"set_lockdown","data":{"enabled":true}}
```
| Command | Data | Notes |
|---|---|---|
| `set_lockdown` | `enabled` | enabling fails with `pin_required` / `dashboard_required` / `no_enforcement_available` |
| `set_allowlist` | `packages[]` | |
| `set_kiosk_launcher` | `enabled` | sidecar acts as home app (boot start + crash recovery); device owner forces it, otherwise the user picks it in Android settings |
| `set_target_package` | `package` | default: HA companion (full or minimal) |
| `launch_app` | `package`, optional `path` | `path` deep-links the HA app via `homeassistant://navigate/<path>` |
| `bring_to_front` | optional `path` | foregrounds the HA app by intent; never restarts it |
| `screen` | `on` | off needs device owner or accessibility |
| `set_brightness` | `level` 0-255 | needs *modify system settings* |
| `set_keep_screen_on` | `enabled` | |
| `set_config` | `config{key: value}` | any display/presence/camera/glance/theme setting (see `cfg` in state, docs/DISPLAY.md) |
| (`set_config` result) | | returns `{config: {...}}`, the validated config; dashboard values are reduced to paths, invalid ones fail with `invalid_value` |
| `external_presence` | `present` | HA presence entities → tablet |
| `external_night` | `night` (bool or null) | HA night entity or the `enter_night_mode` / `exit_night_mode` actions → tablet; null falls back to the schedule |
| `glance_items` | `items[{name,value}]` | values for the glance screen |
| `show_glance` / `hide_glance` | | |
| `set_alarm` | `alarm{id,hour,minute,days[1-7],label,enabled,snooze_minutes}` | empty `days` = once |
| `cancel_alarm` / `stop_alarm` / `snooze_alarm` / `get_alarms` | | `stop_alarm` / `snooze_alarm` also end a ringing timer |
| `set_alarm_enabled` | `id`, `enabled` | |
| `skip_next_alarm` | `id?` | repeating: next occurrence is skipped (again = undo); one-shot: disabled; no id = the alarm that rings next |
| `mute_alarms` / `unmute_alarms` | `until_ms?` (none = until unmuted) | muted alarms do not ring, keep their schedule, fire `alarm_skipped` (`reason: muted`) |
| `start_timer` | `id`, `label`, `kind` (`countdown`/`countup`), `duration_s` (countdown) | same `id` restarts it; max 20 timers, 1 s..99 h |
| `pause_timer` / `resume_timer` / `cancel_timer` | `id` | `cancel_timer` removes without ringing |
| `adjust_timer` | `id`, `delta_s` | add/remove time on a countdown; on a finished one it runs again |
| `get_timers` | | |
| `heal_dashboard` | `reason` | restart requested by Home Assistant (beacon silent): answers `{healed, why?}`; refused (`screen_off`, `busy`, `not_in_front`, `rate_limited`); needs neither the watchdog switch nor accessibility |
| `voice_listen` | | open the assistant page and start a push-to-talk turn (the HA services `listen` / button *Start listening*); errors: `not_connected`, `mic_permission`, `mic_busy`, `mic_failed` |
| `voice_cancel` | | end the running turn and close the page |
| `voice_announce` | `url`, `message`, `preannounce_url?` | play the sound and the announcement; answers when playback ended (`playback_failed` on an error) |
| `restart_companion` | | closes and relaunches the Home Assistant app now (device owner: hide + unhide) |

**Dashboard beacon** (Home Assistant side, not tablet protocol): websocket commands `ha_sidecar/beacon` (`tablet`, `state` active|inactive,
`reason`, `path`) and `ha_sidecar/tablets`; bus events `dashboard_unresponsive`, `dashboard_navigate_attempt`, `dashboard_recovered`.

**Companion app watchdog** (settings `watchdog`, `watchdog_action` = `restart`/`notify`, `watchdog_probe_s`, `watchdog_startup_s`
via `set_config`). State carries `watchdog`: `{enabled, state (off|ok|idle|no_accessibility|unresponsive|restarting|gave_up),
responsive, restarts, last_reason, last_restart_at}`. Events: `companion_unresponsive` (`reason`: `ui_frozen`|`anr`|
`startup_hang`|`manual`, `action`), `companion_restarted` (`reason`, `method`: `anr_close`|`hide_unhide`|`relaunch_only`, `count`),
`companion_restart_gave_up` (after 3 restarts in 10 minutes).

**Timers.** A countdown rings when it ends (native alarm sound, full-screen page, "+1 min" snooze). It then stays `finished`
with `finished_at` set, and the UI shows the time over (`+0:24`) counting up until it is dismissed (dismiss = remove). If
the ring times out it is only silenced and stays listed. Timer events: `timer_started`, `timer_paused`, `timer_resumed`,
`timer_extended`, `timer_finished`, `timer_snoozed`, `timer_dismissed` (`reason`), `timer_ring_timeout`, `timer_cancelled`,
each with `id`, `label`, `kind`, `duration_s`. State additionally carries `timers` and `alarms` (lists), `alarms_muted`,
`alarms_muted_until`, `timer_ringing`.
| `open_system_update` | | opens the screen only; temporarily allowlists Settings |
| `run_system_update` | | opens the screen and taps through it via the accessibility service (`needs_accessibility` otherwise) |
| `install_system_update` | `uri` | device owner, A/B devices, caller supplies the OTA zip |
| `reboot` | | device owner |

Unknown commands → `unknown_command`. Commands time out after 20 s on the HA side.

Voice: `{"type":"voice_event","session":id,"event":"stt-end|intent-end|tts-end|run-end|error|...","data":{...}}` (trimmed Assist
pipeline events) and the command `voice_announce` `{url, message, preannounce_url}`, answered when playback ended.

## Security notes

- The token is the only credential; treat it like a password. It is shown once in the config flow and stored in the config entry.
- Remote *disable* of lockdown is intentionally possible (HA is the admin). Remote *enable* requires a PIN on the device so
  nobody gets locked into a tablet they can't leave.
- TODO: QR pairing, token rotation, per-command audit log.
