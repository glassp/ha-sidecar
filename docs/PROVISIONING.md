# Provisioning

## Device owner (recommended)

Requirements: no other device owner, **no accounts on the device** (Google included) and a single user. Easiest on a freshly reset
tablet, skipping the account step in the setup wizard, but a factory reset is *not* needed on a tablet that is already set up:

1. Settings → Passwords & accounts (or Accounts): note which accounts there are, then remove all of them (Google, Samsung, ...).
   Settings → System → Multiple users: remove any extra user or guest. Disable "Work" or "Clone" profiles if present.
2. ```bash
   adb install app-release.apk          # the release build
   adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver
   ```
   Expected: `Success: Device owner set to package ...`.
3. Add the accounts back (Settings → Accounts → Add account). Having a device owner does not stop the Play Store from installing
   and updating the Home Assistant app, and the sidecar does not restrict accounts.

Failure messages and what they mean:
- `... there are already some accounts on the device`: step 1 was not complete (look for accounts that are hidden, such as a
  Samsung or Xiaomi account, or a work profile).
- `... already several users` / `... users that are not affiliated`: remove the extra user or profile.
- `... already provisioned`: the manufacturer firmware refuses to set an owner after setup: only a factory reset helps (skip
  the account step in the wizard, then run the command before anything else).
- `Neither user 0 nor current user is allowed to add ...`: a profile or user restriction; remove the extra profile first.

It cannot be tried on a device from here: the answer depends on the tablet's make and Android version, so the outcome of the
three commands is the test.

### Giving it up again (no factory reset)

System → Device owner → tap the row → enter the kiosk PIN → *Remove*. The sidecar ends the lock, undoes every policy it set
(lock-task packages, status bar, home preference, stay-on-while-charging, the companion app if the watchdog had hidden it) and calls
`clearDeviceOwnerApp`. Nothing is erased; the accessibility guard takes over as the lock, and the adb command above makes the
tablet device owner again (checked on the emulator: set → remove → set). Without a PIN set the dialog only asks to confirm.

Notes learned while testing:
- Android reads the admin's declared policies (`res/xml/device_admin.xml`) **when ownership is set**. A new sidecar
  version that adds a policy needs the device provisioned again (give up ownership as above, then `dpm set-device-owner`).
- `dpm remove-active-admin` does not work for a device owner, and neither does uninstalling the app: use the Remove button, or
  a factory reset.

## Accessibility fallback

Settings → Accessibility → HA Sidecar kiosk guard → On. The service only inspects window content while a
HA-triggered system update is running, and then only for the system update packages (see ARCHITECTURE.md). On Android 13+ sideloaded apps need *Allow restricted settings* first
(App info → ⋮).

## Companion app settings

- Settings → Companion app → *Use as Home app (launcher)* and *Fullscreen*.
- Grant *Draw over other apps* (also needed by the sidecar).
- Pick a dashboard as the app's home page; kiosk lockdown only keeps the app in front, it does not choose the page.
