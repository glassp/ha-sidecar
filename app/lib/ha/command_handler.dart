import 'package:flutter/services.dart';

import '../platform/kiosk_platform.dart';
import 'sidecar_client.dart';

/// Maps protocol commands (docs/PROTOCOL.md) to platform calls.
class CommandRouter {
  CommandRouter(this.platform);
  final KioskPlatform platform;

  Future<Map<String, dynamic>?> handle(String command, Map<String, dynamic> data) async {
    try {
      return await _dispatch(command, data);
    } on PlatformException catch (e) {
      throw CommandException(e.code, e.message);
    }
  }

  Future<Map<String, dynamic>?> _dispatch(String command, Map<String, dynamic> d) async {
    switch (command) {
      case 'set_lockdown':
        await platform.setLockdown(d['enabled'] == true);
      case 'set_allowlist':
        await platform.setAllowlist((d['packages'] as List).cast<String>());
      case 'set_kiosk_launcher':
        await platform.setKioskLauncher(d['enabled'] == true);
      case 'set_target_package':
        await platform.setTargetPackage(d['package'] as String?);
      case 'launch_app':
        if (!await platform.launchApp(d['package'] as String, path: d['path'] as String?)) {
          throw CommandException('launch_failed', 'package not installed or launch blocked');
        }
      case 'bring_to_front':
        if (!await platform.bringHaToFront(path: d['path'] as String?)) {
          throw CommandException('launch_failed', 'HA app not installed or launch blocked');
        }
      case 'screen':
        d['on'] == true ? await platform.wakeScreen() : await platform.sleepScreen();
      case 'set_brightness':
        await platform.setBrightness(d['level'] as int);
      case 'set_keep_screen_on':
        await platform.setKeepScreenOn(d['enabled'] == true);
      case 'set_config':
        await platform.setDisplayConfig(Map<String, dynamic>.from(d['config'] as Map));
      case 'external_presence':
        await platform.setExternalPresence(d['present'] == true);
      case 'external_night':
        await platform.setExternalNight(d['night'] as bool?);
      case 'glance_items':
        await platform.setGlanceItems(((d['items'] ?? const []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      case 'show_glance':
        await platform.showGlance();
      case 'hide_glance':
        await platform.hideGlance();
      case 'set_alarm':
        await platform.upsertAlarm(AlarmSpec.fromMap((d['alarm'] as Map).cast<String, dynamic>()));
      case 'cancel_alarm':
        await platform.removeAlarm(d['id'] as String);
      case 'stop_alarm':
        await platform.stopAlarm();
      case 'snooze_alarm':
        await platform.snoozeAlarm();
      case 'open_system_update':
        await platform.openSettings('system_update');
      case 'run_system_update':
        await platform.runSystemUpdate();
      case 'install_system_update':
        await platform.installSystemUpdate(d['uri'] as String);
      case 'reboot':
        await platform.reboot();
      case 'get_alarms':
        final alarms = await platform.getAlarms();
        return {
          'alarms': [
            for (final a in alarms) {...a.toMap(), 'next': a.next}
          ]
        };
      default:
        throw CommandException('unknown_command', command);
    }
    return null;
  }
}
