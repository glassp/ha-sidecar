# Architecture

```
┌────────────── Android tablet ──────────────┐            ┌──────── Home Assistant ────────┐
│ HA companion app  (dashboard, in front)    │            │ custom_components/ha_sidecar   │
│                                            │            │  ├ WebSocket view /api/ha_sidecar/ws
│ HA Sidecar (Flutter)                       │  outbound  │  ├ SidecarDevice (state, cmds) │
│  ├ Dart: SidecarClient ────────────────────┼──WebSocket─┼─▶├ entities: switch, sensor…   │
│  │       CommandRouter, UI, (voice later)  │            │  └ services + bus events       │
│  └ Kotlin (platform channel)               │            └────────────────────────────────┘
│     ├ KioskController   lockdown policy    │
│     ├ DeviceAdminReceiver  (device owner)  │
│     ├ AccessibilityService (fallback guard)│
│     ├ HotCorner + PinActivity (exit)       │
│     ├ Alarm{Scheduler,Receiver,Service,Activity}
│     └ KeepAliveService                     │
└────────────────────────────────────────────┘
```

## Principles

- **Enforcement lives in Kotlin, not Dart.** Lockdown flag, allowlist, PIN hash and alarms are persisted natively and
  enforced by services/receivers, so a killed Flutter engine does not unlock the tablet or miss an alarm.
- **Dart is the portable part.** Everything OS-specific is behind `KioskPlatform`
  (`app/lib/platform/kiosk_platform.dart`). A future iOS/desktop port implements that interface; the HA client, UI and
  voice code stay.
- **The tablet connects out.** No inbound port, works behind NAT/reverse proxy, HA pushes commands over the same socket.
- **Sidecar, not fork.** The HA companion app is untouched, so its weekly releases never need backporting. Coupling is
  limited to its package name and its own launcher/fullscreen settings.

## Enforcement modes

| | Device owner | Accessibility fallback |
|---|---|---|
| Mechanism | `setLockTaskPackages` + `setLockTaskFeatures(NONE)` + HA app launched with `setLockTaskEnabled` | `TYPE_WINDOW_STATE_CHANGED` listener bounces non-allowlisted foreground apps, closes the shade, bounces recents |
| System UI | Hidden by the OS | Visible for a split second, then dismissed |
| Bypass resistance | High (survives until factory reset / PIN) | Low: user can disable the service in Settings if they can reach Settings (Settings is not allowlisted, so it is bounced, but timing races exist) |
| Setup | One-time `adb`, device must have no accounts | Toggle in system accessibility settings |
| Extra | Reboot, `lockNow`, stay-awake, OS update callback | Screen lock via global action, update-screen tapping |

## Home role and lifecycle

`HomeActivity` (HOME category, invisible) is the lifecycle owner when *Act as home app* is on. Android starts the home
app at boot and again whenever the task stack is empty, so one mechanism covers: boot start, Home button, HA app
crash/force-stop, lock-task exit. It starts `KeepAliveService` (headless engine, overlay, policy), then launches the HA
app (`lockTask` + `CLEAR_TASK` when lockdown is on; plain reorder-to-front otherwise). Device owner sets itself as home
via `addPersistentPreferredActivity`; others pick it in Android settings (`ROLE_HOME`). There is deliberately no
polling for *crashes*: the OS tells us when the HA app is gone. A *frozen* (not dead) HA app is handled by the opt-in
watchdog below; without the home role or the accessibility service nothing recovers a crashed HA app.

## Watchdog (opt-in, phase 2.5)

`CompanionWatchdog` runs in the keep-alive service. Signals: an accessibility UI probe of the companion app (null root node =
frozen; run on a worker thread with a timeout because the call goes to the frozen app), the ANR dialog (matched by view id),
and a start-up expectation after a launch the sidecar issued. Recovery: "Close app" on the ANR dialog, or device-owner
`setApplicationHidden` true/false plus relaunch (`pm suspend` does not kill a stopped process, hide does); at most 3 restarts
per 10 minutes, never while an alarm rings, the PIN is open or the screen is off. Page-level hangs inside a live WebView are
reported by the *beacon card* in the dashboard: the integration tracks it and, if the user enabled that option, first sends a
navigate intent and then asks the tablet to restart the app (`heal_dashboard`, same gating and limit). Details: ROADMAP 2.5.

## Foregrounding the HA app

Plain intents only: the launcher intent with `FLAG_ACTIVITY_REORDER_TO_FRONT` (no task reset, so the dashboard is not
reloaded), or `homeassistant://navigate/<path>` with `setPackage` to also switch dashboard. When the accessibility
service is enabled the intent is started from *its* context, which is exempt from the background-activity-start
restrictions. Without it we depend on the overlay permission. (Whether the companion app comes to front on a deep link
when it is already running is not documented upstream - test.)

## System update automation

`run_system_update` arms `UpdateAutomation` for 30 min, temporarily allowlists Settings/GMS, opens the update screen and
the accessibility service taps buttons whose **exact visible label** matches a list (check/download/install/restart,
English + German). Unlike the rest of the service this reads window content, so:
- it is armed only by an authenticated HA command and expires,
- it only inspects `com.android.settings`, `com.google.android.gms` and the Pixel updater package,
- each tap is reported to HA (`update_automation_step`).
Label matching is best-effort; OEM update screens will need extra labels. Android restarts the device itself at the end.

## PIN exit

An invisible 72dp window in the top-left corner counts taps (5 within 5 s) and opens the Flutter `/pin` page (see
[UI.md](UI.md); `FLAG_SECURE` in release builds). The check itself stays native. PBKDF2-HMAC-SHA256 (120k iterations, per-device salt), lockout after 5 failures with
exponential back-off. Window type: `TYPE_ACCESSIBILITY_OVERLAY` when the accessibility service runs (no permission needed),
else `TYPE_APPLICATION_OVERLAY` (needs *draw over other apps*).

## Known platform constraints

- **Starting activities from the background** (re-launching the HA app after a bounce or a remote `launch_app`) is
  restricted on Android 10+. Exemptions we rely on: a visible overlay window, an enabled accessibility service,
  an alarm-clock alarm. This is why the setup screen asks for *draw over other apps* even in device-owner mode.
- **Stale dashboards** cannot be fixed from outside the companion app (no access to its WebView cache). The sidecar can
  relaunch the app and, with device owner, reboot nightly; a proper fix needs upstream (`command_reset_frontend_cache`
  is an open request, home-assistant/android#5822).
- Amazon Fire tablets cannot be provisioned as device owner this way; use the fallback.
