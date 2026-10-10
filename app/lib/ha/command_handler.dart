import 'package:flutter/services.dart';

import '../platform/kiosk_platform.dart';
import '../voice/voice_controller.dart';
import 'sidecar_client.dart';

/// Maps protocol commands (docs/PROTOCOL.md) to platform calls.
class CommandRouter {
  CommandRouter(this.platform, {this.voice});
  final KioskPlatform platform;
  final VoiceController? voice;

  Future<Map<String, dynamic>?> handle(
    String command,
    Map<String, dynamic> data,
  ) async {
    try {
      return await _dispatch(command, data);
    } on PlatformException catch (e) {
      throw CommandException(e.code, e.message);
    }
  }

  Future<Map<String, dynamic>?> _dispatch(
    String command,
    Map<String, dynamic> d,
  ) async {
    switch (command) {
      case 'voice_announce':
        final v = voice;
        if (v == null) {
          throw CommandException('unsupported', 'voice is not available');
        }
        try {
          await v.announce(
            url: d['url'] as String? ?? '',
            message: d['message'] as String? ?? '',
            preannounceUrl: d['preannounce_url'] as String?,
          );
        } on StateError catch (e) {
          throw CommandException('playback_failed', e.message);
        }
      case 'voice_conversation':
        final v = voice;
        if (v == null) {
          throw CommandException('unsupported', 'voice is not available');
        }
        try {
          await v.conversation(
            url: d['url'] as String? ?? '',
            message: d['message'] as String? ?? '',
            preannounceUrl: d['preannounce_url'] as String?,
          );
        } on StateError catch (e) {
          throw CommandException('playback_failed', e.message);
        }
      case 'voice_listen':
        final err = await voice?.listen();
        if (err != null) {
          throw CommandException(err, 'could not start listening');
        }
      case 'download_wake_word':
        await platform.downloadWakeWord(d['id'] as String? ?? '');
      case 'voice_cancel':
        await voice?.cancel();
      case 'set_lockdown':
        await platform.setLockdown(d['enabled'] == true);
      case 'set_allowlist':
        await platform.setAllowlist((d['packages'] as List).cast<String>());
      case 'set_kiosk_launcher':
        await platform.setKioskLauncher(d['enabled'] == true);
      case 'set_target_package':
        await platform.setTargetPackage(d['package'] as String?);
      case 'launch_app':
        if (!await platform.launchApp(
          d['package'] as String,
          path: d['path'] as String?,
        )) {
          throw CommandException(
            'launch_failed',
            'package not installed or launch blocked',
          );
        }
      case 'bring_to_front':
        if (!await platform.bringHaToFront(path: d['path'] as String?)) {
          throw CommandException(
            'launch_failed',
            'HA app not installed or launch blocked',
          );
        }
      case 'screen':
        d['on'] == true
            ? await platform.wakeScreen()
            : await platform.sleepScreen();
      case 'set_brightness':
        await platform.setBrightness(d['level'] as int);
      case 'set_keep_screen_on':
        await platform.setKeepScreenOn(d['enabled'] == true);
      case 'set_config':
        return {
          'config': await platform.setDisplayConfig(
            Map<String, dynamic>.from(d['config'] as Map),
          ),
        };
      case 'external_presence':
        await platform.setExternalPresence(d['present'] == true);
      case 'external_night':
        await platform.setExternalNight(d['night'] as bool?);
      case 'glance_items':
        await platform.setGlanceItems(
          ((d['items'] ?? const []) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      case 'show_glance':
        await platform.showGlance();
      case 'hide_glance':
        await platform.hideGlance();
      case 'set_alarm':
        await platform.upsertAlarm(
          AlarmSpec.fromMap((d['alarm'] as Map).cast<String, dynamic>()),
        );
      case 'cancel_alarm':
        await platform.removeAlarm(d['id'] as String);
      case 'stop_alarm':
        await platform.stopAlarm();
      case 'snooze_alarm':
        await platform.snoozeAlarm();
      case 'set_alarm_enabled':
        await platform.setAlarmEnabled(d['id'] as String, d['enabled'] == true);
      case 'skip_next_alarm':
        await platform.skipNextAlarm(d['id'] as String?);
      case 'mute_alarms':
        if (d['until_ms'] != null) {
          await platform.setAlarmsMuted(
            until: DateTime.fromMillisecondsSinceEpoch(
              (d['until_ms'] as num).toInt(),
            ),
          );
        } else {
          await platform.setAlarmsMuted(forever: true);
        }
      case 'unmute_alarms':
        await platform.setAlarmsMuted();
      case 'start_timer':
        await platform.startTimer(
          id: d['id'] as String,
          label: (d['label'] ?? '') as String,
          kind: (d['kind'] ?? 'countdown') as String,
          duration: Duration(
            milliseconds: ((d['duration_s'] ?? 0) as num).round() * 1000,
          ),
        );
      case 'pause_timer':
        await platform.pauseTimer(d['id'] as String);
      case 'resume_timer':
        await platform.resumeTimer(d['id'] as String);
      case 'cancel_timer':
        await platform.cancelTimer(d['id'] as String);
      case 'adjust_timer':
        await platform.adjustTimer(
          d['id'] as String,
          Duration(milliseconds: ((d['delta_s'] ?? 0) as num).round() * 1000),
        );
      case 'get_timers':
        final timers = await platform.getTimers();
        return {
          'timers': [
            for (final t in timers)
              {
                'id': t.id,
                'label': t.label,
                'kind': t.kind,
                'state': t.state,
                'duration_s': t.durationMs ~/ 1000,
                'remaining_s': t.remainingMs ~/ 1000,
                'elapsed_s': t.elapsedMs ~/ 1000,
              },
          ],
        };
      case 'heal_dashboard':
        return platform.healDashboard((d['reason'] ?? 'beacon') as String);
      case 'restart_companion':
        await platform.restartCompanion();
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
            for (final a in alarms) {...a.toMap(), 'next': a.next},
          ],
        };
      default:
        throw CommandException('unknown_command', command);
    }
    return null;
  }
}
