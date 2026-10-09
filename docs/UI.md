# App UI

**Everything visible is Flutter.** There are no native screens: even the PIN pad, the ringing alarm and the idle screen are
Flutter pages. (The only other Android components are invisible: the home-app trampoline, the permission-dialog helper, the
touch-watcher and hot-corner overlay windows.)

## Structure

| Piece | Where |
|---|---|
| Navigation (beamer) | `lib/routing.dart` |
| Translations (easy_localization, `en`, `de`) | `assets/translations/*.json`, keys checked by `test/translations_test.dart` |
| Design widgets (cards, tiles, pills, page frame) | `lib/ui/design.dart`, `lib/ui/setting_widgets.dart` |
| All settings in one list (also feeds search) | `lib/settings/registry.dart` |
| What is missing / how to grant it | `lib/health.dart`, `lib/permissions.dart` |
| Pages | `lib/ui/pages/*`, wizard in `lib/ui/wizard/wizard.dart` |

Routes: `/ /kiosk /display /alarms /system` (tabs of one shell page), `/search`, `/settings/:id`, `/allowed-apps`, `/wizard`,
and the full-screen `/pin /alarm /glance`.

## Full-screen pages over other apps

A Flutter engine can only be attached to one activity at a time, so there is **one** Flutter activity (`MainActivity`).
The PIN pad, alarm and idle screen are routes of it. Native code starts it with a `route` extra (`UiHost.show`), the activity
applies the window flags for that route (show over lock screen, turn screen on, no screenshots for the PIN pad in release
builds, immersive for the idle screen) and emits a `ui_route` event so Dart shows the right page; Dart calls `closeUi(route)`
to leave. If the activity was started only for the overlay it finishes, otherwise it returns to the app page.
Alarm *sound* is native (`AlarmService`), so a slow UI start never delays an alarm.

## Setup wizard and settings search

The first-run wizard walks through: welcome, connect, purpose (kiosk vs sensors/alarms only), companion app, kiosk
dashboard, PIN, protection (device owner vs accessibility), permissions (live status, grant button and hint per item),
start-up (home role), brightness, done. The Home page keeps listing whatever is still missing.

Every setting is a `SettingEntry` (id, section, group, translated title/description/keywords, builder). The tabs render the
registry by section and group, and search filters it by title, description, keywords and group; results are the real
controls. Add a setting by adding an entry and its three translation keys (`settings.<id>.title|desc|kw`); the translation
test fails if either language lacks a key.

## Development loop

`flutter run -d <emulator>` with `--pid-file`: `kill -USR1 $(cat pid)` hot reloads, `-USR2` hot restarts. Native changes
(Kotlin, manifest, resources) need a rebuild. `adb shell am start -n dev.glassp.ha_sidecar/.MainActivity --es route /pin`
opens a full-screen page directly.
