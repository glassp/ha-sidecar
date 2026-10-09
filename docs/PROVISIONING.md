# Provisioning

## Device owner (recommended)

Requirements: no Google/other accounts on the device, no other device owner. Easiest on a freshly reset tablet, skipping
the account step in the setup wizard.

```bash
adb install app-release.apk
adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver
```

If it fails with "already several users/accounts": remove accounts (Settings → Accounts) or factory reset.

Notes learned while testing:
- Android reads the admin's declared policies (`res/xml/device_admin.xml`) **when ownership is set**. A new sidecar
  version that adds a policy needs the device re-provisioned (factory reset) before the policy applies.
- A device owner cannot be uninstalled or removed with `dpm remove-active-admin`; only a factory reset (or
  `clearDeviceOwnerApp` from inside the app, not exposed) does. For development, a throwaway emulator is the easy way.
Removing ownership later is only possible via factory reset, or from the app if we add `clearDeviceOwnerApp` (not
implemented on purpose).

## Accessibility fallback

Settings → Accessibility → HA Sidecar kiosk guard → On. The service only inspects window content while a
HA-triggered system update is running, and then only for the system update packages (see ARCHITECTURE.md). On Android 13+ sideloaded apps need *Allow restricted settings* first
(App info → ⋮).

## Companion app settings

- Settings → Companion app → *Use as Home app (launcher)* and *Fullscreen*.
- Grant *Draw over other apps* (also needed by the sidecar).
- Pick a dashboard as the app's home page; kiosk lockdown only keeps the app in front, it does not choose the page.
