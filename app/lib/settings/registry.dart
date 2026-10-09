import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../ha/sidecar_client.dart';
import '../permissions.dart';
import '../platform/kiosk_platform.dart';
import '../ui/allowlist_screen.dart';
import '../ui/design.dart';
import '../ui/dialogs.dart';
import '../ui/setting_widgets.dart';

/// Every setting in the app, in one list: the Kiosk/Display/System pages render it by section and
/// group, and the search screen filters it. A setting added here is automatically searchable.
enum Section {
  kiosk('Kiosk', Icons.lock_outline, 'Dashboards, lock, PIN and start-up'),
  display('Display & presence', Icons.brightness_6_outlined, 'Brightness, night light, presence and camera'),
  system('System', Icons.tune, 'Connection, permissions, updates and appearance');

  const Section(this.label, this.icon, this.subtitle);
  final String label;
  final IconData icon;
  final String subtitle;
}

class SettingEntry {
  const SettingEntry({
    required this.id,
    required this.section,
    required this.group,
    required this.title,
    required this.description,
    this.keywords = const [],
    required this.builder,
  });

  final String id;
  final Section section;
  final String group;
  final String title;
  final String description;
  final List<String> keywords;
  final Widget Function(BuildContext context) builder;

  String get breadcrumb => '${section.label} › $group';
}

String fmtSeconds(double s) {
  final v = s.round();
  if (v < 60) return '$v s';
  if (v < 3600) {
    final m = v ~/ 60;
    final r = v % 60;
    return r == 0 ? '$m min' : '$m min $r s';
  }
  return '${(v / 3600).toStringAsFixed(v % 3600 == 0 ? 0 : 1)} h';
}

List<SettingEntry> buildRegistry(AppController c) {
  DeviceStatus s() => c.status;
  Map<String, dynamic> cfg() => c.status.cfg;
  num n(String k, num fallback) => (cfg()[k] ?? fallback) as num;
  bool b(String k) => cfg()[k] == true;
  String str(String k, String fallback) => (cfg()[k] ?? fallback) as String;

  Future<void> set(BuildContext ctx, String key, Object v) async {
    final err = await c.setConfig(key, v);
    if (err != null && ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(err)));
  }

  SettingEntry switchEntry(String id, Section sec, String group, IconData icon, String title, String desc, String key,
          {List<String> kw = const [], Future<void> Function(BuildContext, bool)? onChanged}) =>
      SettingEntry(
        id: id, section: sec, group: group, title: title, description: desc, keywords: kw,
        builder: (ctx) => SwitchSetting(
          icon: icon, title: title, subtitle: desc, value: b(key),
          onChanged: (v) => onChanged != null ? onChanged(ctx, v) : set(ctx, key, v),
        ),
      );

  SettingEntry sliderEntry(String id, Section sec, String group, IconData icon, String title, String desc, String key,
          {required double min, required double max, required num fallback, int? divisions, String Function(double)? format, List<String> kw = const [], bool asDouble = false}) =>
      SettingEntry(
        id: id, section: sec, group: group, title: title, description: desc, keywords: kw,
        builder: (ctx) => SliderSetting(
          icon: icon, title: title, subtitle: desc, value: n(key, fallback).toDouble(), min: min, max: max, divisions: divisions, format: format,
          onChanged: (v) => set(ctx, key, asDouble ? double.parse(v.toStringAsFixed(1)) : v.round()),
        ),
      );

  SettingEntry timeEntry(String id, String title, String desc, String key, IconData icon) => SettingEntry(
        id: id, section: Section.display, group: 'Night', title: title, description: desc,
        keywords: const ['schedule', 'sleep', 'bedtime', 'hours'],
        builder: (ctx) => TimeSetting(icon: icon, title: title, subtitle: desc, minutes: n(key, 0).toInt(), onChanged: (m) => set(ctx, key, m)),
      );

  final entries = <SettingEntry>[
    // ---------------------------------------------------------------- Kiosk › Dashboards
    SettingEntry(
      id: 'kiosk_dashboard', section: Section.kiosk, group: 'Dashboards',
      title: 'Main dashboard (kiosk)',
      description: 'The Home Assistant dashboard that stays on screen. Required before you can lock the kiosk.',
      keywords: const ['url', 'link', 'lovelace', 'page', 'default', 'wall panel', 'address', 'home screen', 'path', 'kiosk dashboard'],
      builder: (ctx) => DashboardSetting(
        controller: c, configKey: 'kiosk_dashboard', icon: Icons.dashboard_outlined, required: true,
        title: 'Main dashboard (kiosk)',
        help: 'Opened after a restart, when you press Home and when the lock starts. Paste the address from your browser.',
        value: str('kiosk_dashboard', ''),
      ),
    ),
    switchEntry('glance_enabled', Section.kiosk, 'Dashboards', Icons.wb_twilight, 'Show an idle screen',
        'When nobody touches or stands near the tablet for a while, show a calm screen instead of the main dashboard.', 'glance',
        kw: const ['screensaver', 'at a glance', 'idle', 'clock', 'screen saver']),
    SettingEntry(
      id: 'glance_dashboard', section: Section.kiosk, group: 'Dashboards',
      title: 'Idle dashboard (at a glance)',
      description: 'Optional second dashboard for the idle screen, e.g. weather and temperatures. Empty = built-in clock screen.',
      keywords: const ['url', 'link', 'lovelace', 'screensaver', 'weather', 'idle dashboard', 'glance dashboard', 'address'],
      builder: (ctx) => DashboardSetting(
        controller: c, configKey: 'glance_dashboard', icon: Icons.wb_twilight,
        title: 'Idle dashboard (at a glance)',
        help: 'Build it in Home Assistant with any cards (weather, cameras, floor temperatures). A touch or someone nearby returns to the main dashboard. '
            'Leave empty for the built-in clock screen.',
        value: str('glance_dashboard', ''),
      ),
    ),
    sliderEntry('glance_after', Section.kiosk, 'Dashboards', Icons.timer_outlined, 'Show the idle screen after',
        'How long nobody uses or stands near the tablet.', 'glance_after_s',
        min: 30, max: 3600, fallback: 300, format: fmtSeconds, kw: const ['screensaver', 'timeout', 'delay', 'idle time']),

    // ---------------------------------------------------------------- Kiosk › Lock
    SettingEntry(
      id: 'lockdown', section: Section.kiosk, group: 'Lock',
      title: 'Lock the kiosk',
      description: 'Keeps the dashboard on screen and blocks other apps, the notification shade and recents.',
      keywords: const ['lockdown', 'lock', 'kiosk mode', 'block', 'pin', 'lock task', 'pinning'],
      builder: (ctx) {
        final st = s();
        final missing = [
          if (!st.hasPin) 'a PIN',
          if (((cfg()['kiosk_dashboard'] ?? '') as String).isEmpty) 'the kiosk dashboard',
          if (st.mode == EnforcementMode.none) 'kiosk protection',
        ];
        return SwitchSetting(
          icon: st.lockdown ? Icons.lock : Icons.lock_open,
          title: 'Lock the kiosk',
          subtitle: st.lockdown
              ? 'Locked. Only the Home Assistant app${st.allowlist.isEmpty ? '' : ' and your allowed apps'} can be used.'
              : missing.isEmpty
                  ? 'Keeps the dashboard on screen and blocks everything else.'
                  : 'First set up: ${missing.join(', ')}.',
          value: st.lockdown,
          onChanged: (v) => toggleLockdown(ctx, c, v),
        );
      },
    ),
    SettingEntry(
      id: 'pin', section: Section.kiosk, group: 'Lock', title: s().hasPin ? 'Change PIN' : 'Set PIN',
      description: 'The PIN leaves the locked kiosk: tap the top-left corner 5 times, then enter it.',
      keywords: const ['password', 'code', 'unlock', 'exit', 'secret'],
      builder: (ctx) => ActionSetting(
        icon: Icons.pin_outlined,
        title: s().hasPin ? 'Change PIN' : 'Set PIN',
        subtitle: s().hasPin ? 'Tap the top-left corner 5 times on the locked screen, then enter your PIN.' : 'Required before the kiosk can be locked.',
        trailing: s().hasPin ? const Pill('Set', color: Semantic.ok, icon: Icons.check) : const Pill('Required', color: Semantic.warn, icon: Icons.priority_high),
        onTap: () => showPinDialog(ctx, c),
      ),
    ),
    SettingEntry(
      id: 'allowed_apps', section: Section.kiosk, group: 'Lock', title: 'Allowed apps',
      description: 'Other apps that may be opened while the kiosk is locked (the Home Assistant app and the keyboard are always allowed).',
      keywords: const ['allowlist', 'whitelist', 'apps', 'spotify', 'permit'],
      builder: (ctx) => ActionSetting(
        icon: Icons.apps,
        title: 'Allowed apps',
        subtitle: s().allowlist.isEmpty ? 'Only the Home Assistant app' : '${s().allowlist.length} extra app${s().allowlist.length == 1 ? '' : 's'}',
        onTap: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => AllowlistScreen(controller: c))),
      ),
    ),
    SettingEntry(
      id: 'protection', section: Section.kiosk, group: 'Lock', title: 'Kiosk protection',
      description: 'How strongly the lock is enforced: device owner (strongest) or the accessibility guard.',
      keywords: const ['device owner', 'accessibility', 'enforcement', 'lock task', 'adb', 'dpm', 'guard'],
      builder: (ctx) {
        final st = s();
        final (label, color, icon) = switch (st.mode) {
          EnforcementMode.deviceOwner => ('Device owner', Semantic.ok, Icons.verified_user),
          EnforcementMode.accessibility => ('Accessibility guard', Semantic.warn, Icons.shield_outlined),
          EnforcementMode.none => ('Not protected', Semantic.bad, Icons.gpp_maybe_outlined),
        };
        return ActionSetting(
          icon: icon,
          title: 'Kiosk protection',
          subtitle: switch (st.mode) {
            EnforcementMode.deviceOwner => 'Strongest: Android itself blocks the system UI.',
            EnforcementMode.accessibility => 'Good: other apps are sent back. Device owner is stronger.',
            EnforcementMode.none => 'Turn on the accessibility guard or become device owner to lock the kiosk.',
          },
          color: color,
          trailing: Pill(label, color: color),
          onTap: () => showProtectionSheet(ctx, c),
        );
      },
    ),

    // ---------------------------------------------------------------- Kiosk › Start & screen
    SettingEntry(
      id: 'home_app', section: Section.kiosk, group: 'Start & screen', title: 'Start automatically',
      description: 'Act as the home app: starts after a reboot and re-opens the Home Assistant app when it closes or crashes.',
      keywords: const ['launcher', 'boot', 'autostart', 'home app', 'crash', 'recover', 'startup', 'default home'],
      builder: (ctx) => SwitchSetting(
        icon: Icons.home_outlined,
        title: 'Start automatically',
        subtitle: !s().kioskLauncher
            ? 'Starts after a reboot and brings the Home Assistant app back if it closes.'
            : s().isHomeApp
                ? 'Active. This app is the default home app.'
                : s().deviceOwner
                    ? 'Applying…'
                    : 'Almost done: choose "HA Sidecar" as the default home app in Android.',
        value: s().kioskLauncher,
        onChanged: (v) async {
          await c.platform.setKioskLauncher(v);
          if (v && !s().deviceOwner) await c.platform.openSettings('home');
          await c.refresh();
        },
      ),
    ),
    SettingEntry(
      id: 'keep_screen_on', section: Section.kiosk, group: 'Start & screen', title: 'Keep the screen on',
      description: 'Stops the screen from switching off by itself.',
      keywords: const ['awake', 'sleep', 'timeout', 'screen off', 'wake lock'],
      builder: (ctx) => SwitchSetting(
        icon: Icons.light_mode_outlined, title: 'Keep the screen on', subtitle: 'Stops the screen from switching off by itself.',
        value: s().keepScreenOn,
        onChanged: (v) async {
          await c.platform.setKeepScreenOn(v);
          await c.refresh();
        },
      ),
    ),
    SettingEntry(
      id: 'companion_app', section: Section.kiosk, group: 'Start & screen', title: 'Home Assistant app',
      description: 'The official Home Assistant companion app that shows your dashboard.',
      keywords: const ['companion', 'install', 'package', 'app'],
      builder: (ctx) {
        final found = s().companionPackages;
        return ActionSetting(
          icon: Icons.home_work_outlined,
          title: 'Home Assistant app',
          subtitle: found.isEmpty
              ? 'Not found. Install the Home Assistant companion app and sign in to your server.'
              : 'Found: ${found.map((p) => p.endsWith('.minimal') ? 'minimal' : 'full').join(', ')} version',
          trailing: found.isEmpty ? const Pill('Missing', color: Semantic.bad) : const Pill('Installed', color: Semantic.ok, icon: Icons.check),
          onTap: () async {
            await c.refresh();
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(s().companionPackages.isEmpty ? 'Still not installed.' : 'Home Assistant app found.'),
              ));
            }
          },
        );
      },
    ),

    // ---------------------------------------------------------------- Display › Brightness
    SettingEntry(
      id: 'brightness_mode', section: Section.display, group: 'Brightness', title: 'Brightness control',
      description: 'Manual leaves brightness alone. Auto follows day and night. Day or Night forces one of them.',
      keywords: const ['auto dim', 'dimming', 'night mode', 'day mode', 'automatic', 'backlight'],
      builder: (ctx) => SegmentedSetting(
        icon: Icons.brightness_auto,
        title: 'Brightness control',
        subtitle: 'Manual leaves brightness alone. Auto follows day and night. Day or Night forces one of them.',
        options: const {'manual': 'Manual', 'auto': 'Auto', 'day': 'Day', 'night': 'Night'},
        value: str('mode', 'manual'),
        onChanged: (v) => set(ctx, 'mode', v),
      ),
    ),

    // ---------------------------------------------------------------- Display › Day
    sliderEntry('day_level', Section.display, 'Day', Icons.wb_sunny_outlined, 'Day brightness', 'While the tablet is in use or someone is near.', 'day_level',
        min: 0, max: 255, fallback: 200, kw: const ['bright', 'backlight', 'high']),
    switchEntry('auto_dim', Section.display, 'Day', Icons.brightness_medium, 'Dim when idle',
        'Lower the brightness when nobody uses or stands near the tablet.', 'auto_dim', kw: const ['autodim', 'auto dim', 'idle']),
    sliderEntry('day_dim_level', Section.display, 'Day', Icons.brightness_low, 'Idle brightness', 'Brightness while dimmed during the day.', 'day_dim_level',
        min: 0, max: 255, fallback: 60, kw: const ['dim level']),
    sliderEntry('dim_after', Section.display, 'Day', Icons.timer_outlined, 'Dim after', 'How long without touch or presence before dimming.', 'dim_after_s',
        min: 10, max: 1800, fallback: 120, format: fmtSeconds, kw: const ['idle time', 'timeout']),

    // ---------------------------------------------------------------- Display › Night
    timeEntry('night_start', 'Night starts', 'From this time the night brightness is used.', 'night_start', Icons.bedtime_outlined),
    timeEntry('night_end', 'Night ends', 'From this time the day brightness is used again.', 'night_end', Icons.wb_twilight),
    sliderEntry('night_level', Section.display, 'Night', Icons.nightlight_outlined, 'Night brightness', 'Very dim base brightness at night.', 'night_level',
        min: 0, max: 255, fallback: 6, kw: const ['dark', 'low']),
    switchEntry('night_light', Section.display, 'Night', Icons.lightbulb_outline, 'Night light',
        'Brighten the screen a little when someone walks past, so you can see the floor.', 'night_light',
        kw: const ['nightlight', 'walk past', 'floor', 'presence', 'path light']),
    sliderEntry('night_light_level', Section.display, 'Night', Icons.lightbulb, 'Night light brightness', 'Brightness while someone is near at night.', 'night_light_level',
        min: 0, max: 255, fallback: 50, kw: const ['floor']),
    sliderEntry('night_touch_level', Section.display, 'Night', Icons.touch_app_outlined, 'Brightness after a touch', 'Brightness for a moment after you touch the screen at night.', 'night_touch_level',
        min: 0, max: 255, fallback: 120),
    sliderEntry('night_hold', Section.display, 'Night', Icons.timer_outlined, 'Keep after a touch', 'How long the touch brightness stays.', 'night_hold_s',
        min: 5, max: 300, fallback: 20, format: fmtSeconds),

    // ---------------------------------------------------------------- Display › Presence
    SettingEntry(
      id: 'presence_sources', section: Section.display, group: 'Presence', title: 'Presence sources',
      description: 'Who counts as "near the tablet": Home Assistant presence sensors and/or the camera.',
      keywords: const ['mmwave', 'pir', 'sensor', 'occupancy', 'motion', 'entities'],
      builder: (ctx) => Tile(
        icon: Icons.sensors,
        title: 'Presence sources',
        subtitle: 'Choose presence sensors in Home Assistant: Settings → Devices & services → HA Sidecar → Configure. '
            'The camera below is optional.',
        trailing: s().presence ? const Pill('Someone near', color: Semantic.ok, icon: Icons.person) : const Pill('Nobody near'),
      ),
    ),
    sliderEntry('presence_hold', Section.display, 'Presence', Icons.timer_outlined, 'Keep "present" for', 'How long presence is kept after the last detection.', 'presence_hold_s',
        min: 5, max: 300, fallback: 30, format: fmtSeconds),
    sliderEntry('fade', Section.display, 'Presence', Icons.blur_linear, 'Fade time', 'How smoothly brightness changes.', 'fade_s',
        min: 0, max: 10, fallback: 1.5, divisions: 20, format: (v) => '${v.toStringAsFixed(1)} s', asDouble: true, kw: const ['transition', 'smooth']),

    // ---------------------------------------------------------------- Display › Presence camera
    SettingEntry(
      id: 'camera_presence', section: Section.display, group: 'Presence camera', title: 'Detect presence with the camera',
      description: 'Notices movement near the tablet. Nothing is recorded, stored or sent; a notification shows while it runs.',
      keywords: const ['camera', 'motion', 'privacy', 'detect', 'webcam', 'front camera'],
      builder: (ctx) => SwitchSetting(
        icon: Icons.videocam_outlined,
        title: 'Detect presence with the camera',
        subtitle: 'Notices movement near the tablet. Nothing is recorded, stored or sent; a notification shows while it runs.',
        value: b('camera_presence'),
        onChanged: (v) async {
          await set(ctx, 'camera_presence', v);
          if (v && !s().cameraPermission) await c.platform.requestPermission('camera');
        },
      ),
    ),
    SettingEntry(
      id: 'camera_status', section: Section.display, group: 'Presence camera', title: 'Camera status',
      description: 'Whether the presence camera is running and sees movement.',
      keywords: const ['camera', 'permission', 'error', 'running'],
      builder: (ctx) {
        final st = s();
        if (!b('camera_presence')) return const Tile(icon: Icons.videocam_off_outlined, title: 'Camera status', subtitle: 'Off', trailing: Pill('Off'));
        if (!st.cameraPermission) {
          return ActionSetting(
            icon: Icons.warning_amber_rounded, color: Semantic.warn, title: 'Camera permission needed',
            subtitle: 'Allow camera access so movement can be detected.',
            trailing: FilledButton.tonal(onPressed: () => c.platform.requestPermission('camera'), child: const Text('Grant')),
            onTap: () => c.platform.requestPermission('camera'),
          );
        }
        if (st.cameraError != null) {
          return Tile(icon: Icons.error_outline, color: Semantic.bad, title: 'Camera problem', subtitle: st.cameraError);
        }
        return Tile(
          icon: st.cameraActive ? Icons.videocam : Icons.videocam_off_outlined,
          title: 'Camera status',
          subtitle: 'Picture change ${(st.cameraScore * 100).toStringAsFixed(1)} %',
          trailing: st.cameraActive
              ? (st.cameraMotion ? const Pill('Movement', color: Semantic.ok, icon: Icons.directions_walk) : const Pill('Running'))
              : const Pill('Starting…', color: Semantic.warn),
        );
      },
    ),
    SettingEntry(
      id: 'camera_facing', section: Section.display, group: 'Presence camera', title: 'Which camera',
      description: 'Front or back camera.', keywords: const ['camera', 'front', 'back', 'selfie'],
      builder: (ctx) => SegmentedSetting(
        icon: Icons.cameraswitch_outlined, title: 'Which camera', options: const {'front': 'Front', 'back': 'Back'},
        value: str('camera_facing', 'front'), onChanged: (v) => set(ctx, 'camera_facing', v),
      ),
    ),
    sliderEntry('camera_sensitivity', Section.display, 'Presence camera', Icons.tune, 'Sensitivity', 'Higher notices smaller movements (and more false alarms).', 'camera_sensitivity',
        min: 0, max: 100, fallback: 50, format: (v) => '${v.round()} %', kw: const ['camera', 'motion', 'threshold']),
    sliderEntry('camera_fps', Section.display, 'Presence camera', Icons.speed, 'Frame rate', 'Lower saves battery.', 'camera_fps',
        min: 1, max: 10, fallback: 3, divisions: 9, format: (v) => '${v.round()} fps', kw: const ['camera', 'battery', 'fps']),

    // ---------------------------------------------------------------- System › Home Assistant
    SettingEntry(
      id: 'connection', section: Section.system, group: 'Home Assistant', title: 'Connection',
      description: 'The link to your Home Assistant server (pairing token).',
      keywords: const ['pair', 'token', 'url', 'server', 'unpair', 'reconnect', 'integration', 'link'],
      builder: (ctx) {
        final link = c.link;
        return ValueListenableBuilder<LinkState>(
          valueListenable: link ?? ValueNotifier(LinkState.disconnected),
          builder: (_, state, _) {
            final (label, color) = switch (state) {
              LinkState.connected => ('Connected', Semantic.ok),
              LinkState.connecting => ('Connecting…', Semantic.warn),
              LinkState.authFailed => ('Token rejected', Semantic.bad),
              LinkState.disconnected => ('Disconnected', Semantic.bad),
            };
            return ActionSetting(
              icon: Icons.hub_outlined,
              title: 'Connection',
              subtitle: c.settings.haUrl.isEmpty ? 'Not paired' : c.settings.haUrl,
              color: color,
              trailing: Pill(label, color: color),
              onTap: () => showConnectionSheet(ctx, c),
            );
          },
        );
      },
    ),

    // ---------------------------------------------------------------- System › Appearance
    SettingEntry(
      id: 'theme', section: Section.system, group: 'Appearance', title: 'Theme',
      description: 'Light, dark, follow the system, or dark only at night.',
      keywords: const ['dark mode', 'light mode', 'night mode', 'colors', 'appearance'],
      builder: (ctx) => SegmentedSetting(
        icon: Icons.contrast,
        title: 'Theme',
        subtitle: 'Light, dark, follow the system, or dark only at night.',
        options: const {'system': 'System', 'light': 'Light', 'dark': 'Dark', 'night': 'Dark at night'},
        value: str('theme', 'system'),
        onChanged: (v) => set(ctx, 'theme', v),
      ),
    ),

    // ---------------------------------------------------------------- System › Permissions
    for (final p in permissionSpecs)
      SettingEntry(
        id: 'perm_${p.id}', section: Section.system, group: 'Permissions', title: p.title, description: p.why,
        keywords: [p.id, 'permission', 'android', 'allow', 'grant'],
        builder: (ctx) => PermissionRow(spec: p, controller: c),
      ),
    SettingEntry(
      id: 'device_owner', section: Section.system, group: 'Permissions', title: 'Device owner',
      description: 'Optional, strongest kiosk lock. Needs a one-time adb command on a freshly reset tablet.',
      keywords: const ['dpm', 'adb', 'provision', 'managed', 'lock task'],
      builder: (ctx) => ActionSetting(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Device owner',
        subtitle: s().deviceOwner ? 'This tablet is a device owner.' : 'Optional. Tap to see how.',
        trailing: s().deviceOwner ? const Pill('Active', color: Semantic.ok, icon: Icons.check) : const Pill('Not set'),
        onTap: () => showProtectionSheet(ctx, c),
      ),
    ),

    // ---------------------------------------------------------------- System › Updates
    SettingEntry(
      id: 'update', section: Section.system, group: 'Updates', title: 'Android system update',
      description: 'Opens the system update screen and, with the accessibility guard, taps through it.',
      keywords: const ['os update', 'upgrade', 'security patch', 'version', 'firmware'],
      builder: (ctx) => ActionSetting(
        icon: s().pendingUpdate != null ? Icons.system_update : Icons.verified_outlined,
        title: s().pendingUpdate != null ? 'An Android update is available' : 'Android ${s().androidRelease}',
        subtitle: 'Security patch ${s().securityPatch}${s().deviceOwner ? '' : '. Update detection needs device owner.'}',
        trailing: const Text('Check'),
        onTap: () async {
          if (s().accessibilityEnabled) {
            await c.platform.runSystemUpdate();
          } else {
            await c.platform.openSettings('system_update');
          }
        },
      ),
    ),

    // ---------------------------------------------------------------- System › Setup
    SettingEntry(
      id: 'run_setup', section: Section.system, group: 'Setup', title: 'Run the setup wizard again',
      description: 'Walks through connection, dashboard, PIN and permissions step by step.',
      keywords: const ['wizard', 'onboarding', 'guide', 'setup', 'reset', 'first run', 'help'],
      builder: (ctx) => ActionSetting(
        icon: Icons.auto_fix_high,
        title: 'Run the setup wizard again',
        subtitle: 'Walks through connection, dashboard, PIN and permissions step by step.',
        onTap: () => c.restartSetup(),
      ),
    ),
  ];
  return entries;
}

/// Free-text search over title, description, keywords, group and section; every word must match.
List<SettingEntry> searchSettings(List<SettingEntry> all, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  int score(SettingEntry e) {
    var total = 0;
    final title = e.title.toLowerCase();
    final rest = '${e.description} ${e.keywords.join(' ')} ${e.group} ${e.section.label}'.toLowerCase();
    for (final w in words) {
      if (title.contains(w)) {
        total += title.startsWith(w) ? 6 : 4;
      } else if (rest.contains(w)) {
        total += 1;
      } else {
        return 0;
      }
    }
    return total;
  }

  final scored = [for (final e in all) (e, score(e))].where((p) => p.$2 > 0).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final p in scored) p.$1];
}

// -------------------------------------------------------------------------------- sheets

Future<void> showProtectionSheet(BuildContext context, AppController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final s = c.status;
        final t = Theme.of(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kiosk protection', style: t.textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Two ways to keep other apps away from the dashboard. You can use both.'),
              const SizedBox(height: 16),
              GroupCard(children: [
                Tile(
                  icon: Icons.shield_outlined,
                  title: 'Accessibility guard',
                  subtitle: 'Works on any tablet. Sends other apps back and closes the notification shade within a moment.',
                  trailing: s.accessibilityEnabled
                      ? const Pill('On', color: Semantic.ok, icon: Icons.check)
                      : FilledButton.tonal(onPressed: () => c.platform.openSettings('accessibility'), child: const Text('Turn on')),
                ),
                Tile(
                  icon: Icons.verified_user_outlined,
                  title: 'Device owner (strongest)',
                  subtitle: s.deviceOwner
                      ? 'Active: Android itself hides and blocks the system UI.'
                      : 'Android itself hides and blocks the system UI. Needs a factory-reset tablet with no accounts and a computer with adb.',
                  trailing: s.deviceOwner ? const Pill('Active', color: Semantic.ok, icon: Icons.check) : null,
                ),
              ]),
              if (!s.deviceOwner) ...[
                const SizedBox(height: 16),
                Text('To become device owner', style: t.textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('1. Factory reset the tablet and skip adding any account.\n'
                    '2. Install this app and the Home Assistant app.\n'
                    '3. Enable USB debugging and, on a computer, run:'),
                const SizedBox(height: 8),
                const CopyBlock('adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver'),
                const SizedBox(height: 8),
                Text('A device owner cannot be removed afterwards except by a factory reset. Fire tablets are not supported.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
        );
      },
    ),
  );
}

Future<void> showConnectionSheet(BuildContext context, AppController c) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Connection', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(c.settings.haUrl.isEmpty ? 'This tablet is not paired.' : 'Paired with ${c.settings.haUrl}'),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.link_off),
            label: const Text('Pair again with a new token'),
            onPressed: () async {
              Navigator.pop(ctx);
              await c.unpair();
              await c.restartSetup();
            },
          ),
        ]),
      ),
    ),
  );
}
