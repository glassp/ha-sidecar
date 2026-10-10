import 'package:flutter/services.dart';

import 'kiosk_platform.dart';

/// Android implementation, backed by the Kotlin code in android/app/src/main/kotlin.
class AndroidKioskPlatform implements KioskPlatform {
  static const _methods = MethodChannel('dev.glassp.ha_sidecar/platform');
  static const _events = EventChannel('dev.glassp.ha_sidecar/events');

  Stream<PlatformEvent>? _stream;

  @override
  Stream<PlatformEvent> get events =>
      _stream ??= _events.receiveBroadcastStream().map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return PlatformEvent(
          m['type'] as String,
          Map<String, dynamic>.from((m['data'] as Map?) ?? const {}),
        );
      }).asBroadcastStream();

  Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) =>
      _methods.invokeMethod<T>(method, args);

  @override
  Future<DeviceStatus> getStatus() async => DeviceStatus(
    Map<String, dynamic>.from(await _call<Map>('getStatus') ?? const {}),
  );

  @override
  Future<void> setLockdown(bool enabled) =>
      _call('setLockdown', {'enabled': enabled});

  @override
  Future<void> setAllowlist(List<String> packages) =>
      _call('setAllowlist', {'packages': packages});

  @override
  Future<void> setTargetPackage(String? package) =>
      _call('setTargetPackage', {'package': package});

  @override
  Future<void> setKioskLauncher(bool enabled) =>
      _call('setKioskLauncher', {'enabled': enabled});

  @override
  Future<void> setPin(String pin) => _call('setPin', {'pin': pin});

  @override
  Future<bool> launchApp(String package, {String? path}) async =>
      await _call<bool>('launchApp', {'package': package, 'path': path}) ??
      false;

  @override
  Future<bool> bringHaToFront({String? path}) async =>
      await _call<bool>('bringHaToFront', {'path': path}) ?? false;

  @override
  Future<void> runSystemUpdate() => _call('runSystemUpdate');

  @override
  Future<List<LaunchableApp>> listLaunchableApps() async {
    final list = await _call<List>('listLaunchableApps') ?? const [];
    return [
      for (final e in list)
        LaunchableApp((e as Map)['package'] as String, e['label'] as String),
    ];
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) =>
      _call('setKeepScreenOn', {'enabled': enabled});

  @override
  Future<void> wakeScreen() => _call('wakeScreen');

  @override
  Future<void> sleepScreen() => _call('sleepScreen');

  @override
  Future<void> setBrightness(int level) =>
      _call('setBrightness', {'level': level});

  @override
  Future<Map<String, dynamic>> setDisplayConfig(
    Map<String, dynamic> config,
  ) async => Map<String, dynamic>.from(
    await _call<Map>('setDisplayConfig', {'config': config}) ?? const {},
  );

  @override
  Future<void> setExternalPresence(bool present) =>
      _call('setExternalPresence', {'present': present});

  @override
  Future<void> setExternalNight(bool? night) =>
      _call('setExternalNight', {'night': night});

  @override
  Future<int> unlockWithPin(String pin) async =>
      (await _call<num>('unlockWithPin', {'pin': pin}) ?? -1).toInt();

  @override
  Future<void> closeUi(String route) => _call('closeUi', {'route': route});

  @override
  Future<bool> bubbleAvailable() async =>
      (await _call<bool>('bubbleAvailable')) ?? false;

  @override
  Future<void> bubbleUpdate(Map<String, Object?> snapshot) =>
      _call('bubbleUpdate', snapshot);

  @override
  Future<void> bubbleHide() => _call('bubbleHide');

  @override
  Future<void> reportTouch() => _call('reportTouch');

  @override
  Future<void> setGlanceItems(List<Map<String, dynamic>> items) =>
      _call('setGlanceItems', {'items': items});

  @override
  Future<bool> showGlance() async => await _call<bool>('showGlance') ?? false;

  @override
  Future<void> hideGlance() => _call('hideGlance');

  @override
  Future<void> requestPermission(String name) =>
      _call('requestPermission', {'name': name});

  @override
  Future<List<AlarmSpec>> getAlarms() async {
    final list = await _call<List>('getAlarms') ?? const [];
    return [for (final e in list) AlarmSpec.fromMap(e as Map)];
  }

  @override
  Future<void> upsertAlarm(AlarmSpec alarm) =>
      _call('upsertAlarm', {'alarm': alarm.toMap()});

  @override
  Future<void> removeAlarm(String id) => _call('removeAlarm', {'id': id});

  @override
  Future<void> stopAlarm() => _call('stopAlarm');

  @override
  Future<void> snoozeAlarm() => _call('snoozeAlarm');

  @override
  Future<void> setAlarmEnabled(String id, bool enabled) =>
      _call('setAlarmEnabled', {'id': id, 'enabled': enabled});

  @override
  Future<void> skipNextAlarm(String? id) => _call('skipNextAlarm', {'id': id});

  @override
  Future<void> setAlarmsMuted({DateTime? until, bool forever = false}) => _call(
    'setAlarmsMuted',
    {'until_ms': until?.millisecondsSinceEpoch, 'forever': forever},
  );

  @override
  Future<Map<String, dynamic>> healDashboard(String reason) async =>
      Map<String, dynamic>.from(
        await _call<Map>('healDashboard', {'reason': reason}) ?? const {},
      );

  @override
  Future<void> restartCompanion() => _call('restartCompanion');

  @override
  Future<Map<String, dynamic>> startPairing() async =>
      Map<String, dynamic>.from(await _call<Map>('startPairing') ?? const {});

  @override
  Future<void> stopPairing() => _call('stopPairing');

  @override
  Future<void> answerPairing(bool allow) =>
      _call('answerPairing', {'allow': allow});

  @override
  Future<String?> voiceStart(String session) =>
      _call<String>('voiceStart', {'session': session});

  @override
  Future<void> voiceStop() => _call('voiceStop');

  @override
  Future<String?> voicePlay(String url) =>
      _call<String>('voicePlay', {'url': url});

  @override
  Future<void> voicePing(String kind) => _call('voicePing', {'kind': kind});

  @override
  Future<void> voiceVolumeRaise(int percent) =>
      _call('voiceVolumeRaise', {'percent': percent});

  @override
  Future<void> voiceVolumeRestore() => _call('voiceVolumeRestore');

  @override
  Future<void> voiceStopPlayback() => _call('voiceStopPlayback');

  @override
  Future<void> requestMicPermission() => _call('requestMicPermission');

  @override
  Future<void> downloadWakeWord(String id) =>
      _call('downloadWakeWord', {'id': id});

  @override
  Future<void> removeWakeWord(String id) => _call('removeWakeWord', {'id': id});

  @override
  Future<bool> showUi(String route) async =>
      await _call<bool>('showUi', {'route': route}) ?? false;

  @override
  Future<List<TimerSpec>> getTimers() async {
    final list = await _call<List>('getTimers') ?? const [];
    return [for (final e in list) TimerSpec.fromMap(e as Map)];
  }

  @override
  Future<void> startTimer({
    required String id,
    String label = '',
    String kind = 'countdown',
    Duration duration = Duration.zero,
  }) => _call('startTimer', {
    'id': id,
    'label': label,
    'kind': kind,
    'duration_ms': duration.inMilliseconds,
  });

  @override
  Future<void> pauseTimer(String id) => _call('pauseTimer', {'id': id});

  @override
  Future<void> resumeTimer(String id) => _call('resumeTimer', {'id': id});

  @override
  Future<void> cancelTimer(String id) => _call('cancelTimer', {'id': id});

  @override
  Future<void> adjustTimer(String id, Duration delta) =>
      _call('adjustTimer', {'id': id, 'delta_ms': delta.inMilliseconds});

  @override
  Future<void> startKeepAlive() => _call('startKeepAlive');

  @override
  Future<bool> openSettings(String kind) async =>
      await _call<bool>('openSettings', {'kind': kind}) ?? false;

  @override
  Future<void> installSystemUpdate(String uri) =>
      _call('installSystemUpdate', {'uri': uri});

  @override
  Future<void> reboot() => _call('reboot');
}
