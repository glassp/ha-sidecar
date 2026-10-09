import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'platform/kiosk_platform.dart';
import 'ui/design.dart';

/// What the app needs from Android and how to grant it. Texts live in the translation files under
/// `perm.<id>.title|why|hint`; the wizard, the System page and the health checks share this list.
class PermissionSpec {
  const PermissionSpec({
    required this.id,
    required this.icon,
    required this.granted,
    required this.grant,
    this.required = false,
    this.hasHint = true,
  });

  final String id;
  final IconData icon;
  final bool Function(DeviceStatus) granted;
  final Future<void> Function(AppController) grant;
  final bool required;
  final bool hasHint;

  String get title => 'perm.$id.title'.tr();
  String get why => 'perm.$id.why'.tr();
  String? get hint => hasHint ? 'perm.$id.hint'.tr() : null;
}

final List<PermissionSpec> permissionSpecs = [
  PermissionSpec(
    id: 'overlay',
    icon: Icons.layers_outlined,
    required: true,
    granted: (s) => s.overlayGranted,
    grant: (c) async => c.platform.openSettings('overlay').then((_) {}),
  ),
  PermissionSpec(
    id: 'accessibility',
    icon: Icons.accessibility_new,
    granted: (s) => s.accessibilityEnabled,
    grant: (c) async => c.platform.openSettings('accessibility').then((_) {}),
  ),
  PermissionSpec(
    id: 'write_settings',
    icon: Icons.brightness_6_outlined,
    granted: (s) => s.writeSettingsGranted,
    grant: (c) async => c.platform.openSettings('write_settings').then((_) {}),
  ),
  PermissionSpec(
    id: 'notifications',
    icon: Icons.notifications_outlined,
    granted: (s) => s.notificationsGranted,
    grant: (c) async => c.platform.requestPermission('notifications'),
  ),
  PermissionSpec(
    id: 'battery',
    icon: Icons.battery_charging_full,
    granted: (s) => s.batteryUnrestricted,
    grant: (c) async => c.platform.openSettings('battery').then((_) {}),
  ),
  PermissionSpec(
    id: 'full_screen_intent',
    icon: Icons.alarm_on,
    granted: (s) => s.fullScreenIntentGranted,
    grant: (c) async =>
        c.platform.openSettings('full_screen_intent').then((_) {}),
  ),
];

/// Row with status pill and a grant button; [showWhy] expands the explanation (wizard).
class PermissionRow extends StatelessWidget {
  const PermissionRow({
    super.key,
    required this.spec,
    required this.controller,
    this.showWhy = false,
  });
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
          Row(
            children: [
              IconBadge(
                spec.icon,
                color: ok
                    ? Semantic.ok
                    : (spec.required ? Semantic.warn : null),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spec.title, style: t.textTheme.titleMedium),
                    if (!showWhy)
                      Text(
                        ok
                            ? 'perm.granted'.tr()
                            : (spec.required
                                  ? 'perm.needed'.tr()
                                  : 'perm.recommended'.tr()),
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: ok
                              ? Semantic.ok
                              : t.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (ok)
                Pill('perm.granted'.tr(), color: Semantic.ok, icon: Icons.check)
              else
                FilledButton.tonal(
                  onPressed: () => spec.grant(controller),
                  child: Text('perm.grant'.tr()),
                ),
            ],
          ),
          if (showWhy) ...[
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 6),
              child: Text(
                spec.why,
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (!ok && spec.hint != null)
              Padding(
                padding: const EdgeInsets.only(left: 56, top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 16,
                      color: t.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(spec.hint!, style: t.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
