import 'package:flutter/services.dart';

import 'kiosk_platform.dart';

/// Android implementation, backed by the Kotlin code in android/app/src/main/kotlin.
class AndroidKioskPlatform implements KioskPlatform {
  static const _methods = MethodChannel('dev.glassp.ha_sidecar/platform');
  static const _events = EventChannel('dev.glassp.ha_sidecar/events');

  Stream<PlatformEvent>? _stream;

  @override
  Stream<PlatformEvent> get events => _stream ??= _events.receiveBroadcastStream().map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return PlatformEvent(m['type'] as String, Map<String, dynamic>.from((m['data'] as Map?) ?? const {}));
      }).asBroadcastStream();

  Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) => _methods.invokeMethod<T>(method, args);

  @override
  Future<DeviceStatus> getStatus() async =>
      DeviceStatus(Map<String, dynamic>.from(await _call<Map>('getStatus') ?? const {}));

  @override
  Future<void> setLockdown(bool enabled) => _call('setLockdown', {'enabled': enabled});

  @override
  Future<void> setAllowlist(List<String> packages) => _call('setAllowlist', {'packages': packages});

  @override
  Future<void> setTargetPackage(String? package) => _call('setTargetPackage', {'package': package});

  @override
  Future<void> setKioskLauncher(bool enabled) => _call('setKioskLauncher', {'enabled': enabled});

  @override
  Future<void> setPin(String pin) => _call('setPin', {'pin': pin});

  @override
  Future<bool> launchApp(String package, {String? path}) async =>
      await _call<bool>('launchApp', {'package': package, 'path': path}) ?? false;

  @override
  Future<bool> bringHaToFront({String? path}) async =>
      await _call<bool>('bringHaToFront', {'path': path}) ?? false;

  @override
  Future<void> runSystemUpdate() => _call('runSystemUpdate');

  @override
  Future<List<LaunchableApp>> listLaunchableApps() async {
    final list = await _call<List>('listLaunchableApps') ?? const [];
    return [
      for (final e in list) LaunchableApp((e as Map)['package'] as String, e['label'] as String),
    ];
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) => _call('setKeepScreenOn', {'enabled': enabled});

  @override
  Future<void> wakeScreen() => _call('wakeScreen');

  @override
  Future<void> sleepScreen() => _call('sleepScreen');

  @override
  Future<void> setBrightness(int level) => _call('setBrightness', {'level': level});

  @override
  Future<List<AlarmSpec>> getAlarms() async {
    final list = await _call<List>('getAlarms') ?? const [];
    return [for (final e in list) AlarmSpec.fromMap(e as Map)];
  }

  @override
  Future<void> upsertAlarm(AlarmSpec alarm) => _call('upsertAlarm', {'alarm': alarm.toMap()});

  @override
  Future<void> removeAlarm(String id) => _call('removeAlarm', {'id': id});

  @override
  Future<void> stopAlarm() => _call('stopAlarm');

  @override
  Future<void> snoozeAlarm() => _call('snoozeAlarm');

  @override
  Future<void> startKeepAlive() => _call('startKeepAlive');

  @override
  Future<bool> openSettings(String kind) async => await _call<bool>('openSettings', {'kind': kind}) ?? false;

  @override
  Future<void> installSystemUpdate(String uri) => _call('installSystemUpdate', {'uri': uri});

  @override
  Future<void> reboot() => _call('reboot');
}
