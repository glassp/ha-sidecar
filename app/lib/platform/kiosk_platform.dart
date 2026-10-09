/// Platform abstraction. Everything OS-specific goes through this interface so the Dart
/// side (HA client, UI, voice) stays portable; Android is the only implementation today.
library;

enum EnforcementMode { deviceOwner, accessibility, none }

class DeviceStatus {
  const DeviceStatus(this.raw);
  final Map<String, dynamic> raw;

  static const empty = DeviceStatus({});

  EnforcementMode get mode => switch (raw['mode']) {
        'device_owner' => EnforcementMode.deviceOwner,
        'accessibility' => EnforcementMode.accessibility,
        _ => EnforcementMode.none,
      };

  bool _b(String k) => raw[k] == true;
  bool get deviceOwner => _b('device_owner');
  bool get accessibilityEnabled => _b('accessibility_enabled');
  bool get overlayGranted => _b('overlay_granted');
  bool get writeSettingsGranted => _b('write_settings_granted');
  bool get lockdown => _b('lockdown');
  bool get hasPin => _b('has_pin');
  bool get keepScreenOn => _b('keep_screen_on');
  bool get kioskLauncher => _b('kiosk_launcher');
  bool get isHomeApp => _b('is_home_app');
  bool get alarmRinging => _b('alarm_ringing');
  String? get targetPackage => raw['target_package'] as String?;
  List<String> get allowlist => (raw['allowlist'] as List? ?? const []).cast<String>();
  Map<String, dynamic>? get pendingUpdate => (raw['pending_update'] as Map?)?.cast<String, dynamic>();
  String get securityPatch => (raw['security_patch'] ?? '') as String;
  String get androidRelease => (raw['android_release'] ?? '') as String;
  int? get nextAlarmMillis => raw['next_alarm'] as int?;
}

class PlatformEvent {
  const PlatformEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

class LaunchableApp {
  const LaunchableApp(this.package, this.label);
  final String package;
  final String label;
}

class AlarmSpec {
  const AlarmSpec({
    required this.id,
    required this.hour,
    required this.minute,
    this.days = const [],
    this.label = '',
    this.enabled = true,
    this.snoozeMinutes = 9,
    this.next,
  });

  final String id;
  final int hour;
  final int minute;

  /// ISO weekdays, 1 = Monday .. 7 = Sunday. Empty = one-shot.
  final List<int> days;
  final String label;
  final bool enabled;
  final int snoozeMinutes;
  final int? next;

  factory AlarmSpec.fromMap(Map<dynamic, dynamic> m) => AlarmSpec(
        id: m['id'] as String,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        days: ((m['days'] as List?) ?? const []).cast<int>(),
        label: (m['label'] ?? '') as String,
        enabled: (m['enabled'] ?? true) as bool,
        snoozeMinutes: (m['snooze_minutes'] ?? 9) as int,
        next: m['next'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'days': days,
        'label': label,
        'enabled': enabled,
        'snooze_minutes': snoozeMinutes,
      };
}

abstract class KioskPlatform {
  Stream<PlatformEvent> get events;

  Future<DeviceStatus> getStatus();

  // Lockdown
  Future<void> setLockdown(bool enabled);
  Future<void> setAllowlist(List<String> packages);
  Future<void> setTargetPackage(String? package);

  /// Act as the home app: Android starts us at boot and whenever no task is left.
  Future<void> setKioskLauncher(bool enabled);
  Future<void> setPin(String pin);

  // Apps
  Future<bool> launchApp(String package, {String? path});

  /// Foregrounds the HA companion app via intent; [path] deep-links (`homeassistant://navigate/<path>`).
  Future<bool> bringHaToFront({String? path});
  Future<List<LaunchableApp>> listLaunchableApps();

  // Screen
  Future<void> setKeepScreenOn(bool enabled);
  Future<void> wakeScreen();
  Future<void> sleepScreen();
  Future<void> setBrightness(int level);

  // Alarms
  Future<List<AlarmSpec>> getAlarms();
  Future<void> upsertAlarm(AlarmSpec alarm);
  Future<void> removeAlarm(String id);
  Future<void> stopAlarm();
  Future<void> snoozeAlarm();

  // System
  Future<void> startKeepAlive();
  Future<bool> openSettings(String kind);
  /// Opens the system update screen and taps through it (accessibility service required).
  Future<void> runSystemUpdate();
  Future<void> installSystemUpdate(String uri);
  Future<void> reboot();
}
