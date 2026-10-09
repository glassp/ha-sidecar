import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'platform/kiosk_platform.dart';
import 'ui/design.dart';

/// What the app needs from Android, why, and how to grant it. Used by the setup wizard,
/// the System page and the health checks, so the wording lives in one place.
class PermissionSpec {
  const PermissionSpec({
    required this.id,
    required this.icon,
    required this.title,
    required this.why,
    this.hint,
    required this.granted,
    required this.grant,
    this.required = false,
    this.grantLabel = 'Grant',
  });

  final String id;
  final IconData icon;
  final String title;
  final String why;
  final String? hint; // what to do on the Android screen that opens
  final bool Function(DeviceStatus) granted;
  final Future<void> Function(AppController) grant;
  final bool required;
  final String grantLabel;
}

final List<PermissionSpec> permissionSpecs = [
  PermissionSpec(
    id: 'overlay',
    icon: Icons.layers_outlined,
    title: 'Display over other apps',
    why: 'Lets the sidecar bring the Home Assistant app back to the front, track touches for dimming and show the hidden PIN corner.',
    hint: 'On the next screen switch on "Allow display over other apps" for HA Sidecar.',
    required: true,
    granted: (s) => s.overlayGranted,
    grant: (c) async {
      await c.platform.openSettings('overlay');
    },
  ),
  PermissionSpec(
    id: 'accessibility',
    icon: Icons.accessibility_new,
    title: 'Accessibility guard',
    why: 'Keeps other apps, the notification shade and the recents screen away from the dashboard when this tablet is not a '
        'device owner, and reports which app is in front. It does not read your screen.',
    hint: 'Open "Installed apps" / "Downloaded apps", choose HA Sidecar kiosk guard and switch it on. If Android says '
        '"restricted setting": App info → ⋮ → Allow restricted settings, then try again.',
    granted: (s) => s.accessibilityEnabled,
    grant: (c) async {
      await c.platform.openSettings('accessibility');
    },
  ),
  PermissionSpec(
    id: 'write_settings',
    icon: Icons.brightness_6_outlined,
    title: 'Modify system settings',
    why: 'Needed to change the screen brightness for auto dimming, the night light and remote brightness.',
    hint: 'On the next screen switch on "Allow modifying system settings".',
    granted: (s) => s.writeSettingsGranted,
    grant: (c) async {
      await c.platform.openSettings('write_settings');
    },
  ),
  PermissionSpec(
    id: 'notifications',
    icon: Icons.notifications_outlined,
    title: 'Notifications',
    why: 'Alarms and the camera indicator are shown as notifications, and Android needs one to keep the sidecar running.',
    hint: 'Choose "Allow" in the dialog.',
    granted: (s) => s.notificationsGranted,
    grant: (c) async {
      await c.platform.requestPermission('notifications');
    },
  ),
  PermissionSpec(
    id: 'battery',
    icon: Icons.battery_charging_full,
    title: 'No battery restrictions',
    why: 'Stops Android from pausing the sidecar in the background, which would silence alarms and drop the Home Assistant connection.',
    hint: 'Choose "All apps", find HA Sidecar and set it to "Don\'t optimize".',
    granted: (s) => s.batteryUnrestricted,
    grant: (c) async {
      await c.platform.openSettings('battery');
    },
  ),
  PermissionSpec(
    id: 'full_screen_intent',
    icon: Icons.alarm_on,
    title: 'Full-screen alarms',
    why: 'Lets a ringing alarm take over the screen, also while the kiosk is locked.',
    hint: 'On the next screen switch on "Allow full-screen notifications".',
    granted: (s) => s.fullScreenIntentGranted,
    grant: (c) async {
      await c.platform.openSettings('full_screen_intent');
    },
  ),
];

/// Row with status pill and a grant button; [showWhy] expands the explanation (wizard).
class PermissionRow extends StatelessWidget {
  const PermissionRow({super.key, required this.spec, required this.controller, this.showWhy = false});
  final PermissionSpec spec;
  final AppController controller;
  final bool showWhy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ok = spec.granted(controller.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconBadge(spec.icon, color: ok ? Semantic.ok : (spec.required ? Semantic.warn : null)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(spec.title, style: t.textTheme.titleMedium),
                if (!showWhy)
                  Text(ok ? 'Granted' : (spec.required ? 'Needed' : 'Recommended'),
                      style: t.textTheme.bodyMedium?.copyWith(color: ok ? Semantic.ok : t.colorScheme.onSurfaceVariant)),
              ]),
            ),
            if (ok)
              const Pill('Granted', color: Semantic.ok, icon: Icons.check)
            else
              FilledButton.tonal(onPressed: () => spec.grant(controller), child: Text(spec.grantLabel)),
          ]),
          if (showWhy) ...[
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 6),
              child: Text(spec.why, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
            if (!ok && spec.hint != null)
              Padding(
                padding: const EdgeInsets.only(left: 56, top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.tips_and_updates_outlined, size: 16, color: t.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(spec.hint!, style: t.textTheme.bodySmall)),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}
