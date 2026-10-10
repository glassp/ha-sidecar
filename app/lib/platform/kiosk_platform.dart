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
  bool get isNight => _b('is_night');
  bool get presence => _b('presence');
  bool get cameraInUse => _b('camera_in_use');
  bool get micInUse => _b('mic_in_use');
  bool get cameraPermission => _b('camera_permission');
  bool get micPermission => _b('mic_permission');
  bool get wakeWordListening => _b('wake_word_listening');
  String? get wakeWordError => raw['wake_word_error'] as String?;
  String? get wakeWordDownloading => raw['wake_word_downloading'] as String?;
  double get wakeWordDownloadFraction =>
      (raw['wake_word_download_fraction'] as num?)?.toDouble() ?? 0;
  String? get wakeWordDownloadError =>
      raw['wake_word_download_error'] as String?;
  double get wakeWordScore => (raw['wake_word_score'] as num?)?.toDouble() ?? 0;

  /// The phrases chosen to listen for (installed or not).
  List<Map<String, dynamic>> get activeWakeWords => [
    for (final w in wakeWords)
      if (w['active'] == true) w,
  ];

  /// The wake words the app knows: `{id, phrase, installed, missing_bytes}`.
  List<Map<String, dynamic>> get wakeWords => [
    for (final e in (raw['wake_words'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  bool get notificationsGranted => _b('notifications_granted');
  bool get batteryUnrestricted => _b('battery_unrestricted');
  bool get fullScreenIntentGranted => _b('full_screen_intent_granted');
  List<String> get companionPackages =>
      (raw['companion_packages'] as List? ?? const []).cast<String>();
  bool get glanceShowing => _b('glance_showing');
  List<Map<String, dynamic>> get glanceItems => [
    for (final e in (raw['glance_items'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  Map<String, dynamic>? get ringingAlarm =>
      (raw['ringing_alarm'] as Map?)?.cast<String, dynamic>();
  bool get cameraActive => _b('camera_active');
  bool get cameraMotion => _b('camera_motion');
  String? get cameraError => raw['camera_error'] as String?;
  double get cameraScore => ((raw['camera_score'] ?? 0) as num).toDouble();
  int? get targetBrightness => raw['target_brightness'] as int?;
  String? get displayError => raw['display_error'] as String?;
  Map<String, dynamic> get cfg =>
      Map<String, dynamic>.from((raw['cfg'] as Map?) ?? const {});
  bool get isHomeApp => _b('is_home_app');
  bool get alarmRinging => _b('alarm_ringing');
  String? get targetPackage => raw['target_package'] as String?;
  List<String> get allowlist =>
      (raw['allowlist'] as List? ?? const []).cast<String>();
  Map<String, dynamic>? get pendingUpdate =>
      (raw['pending_update'] as Map?)?.cast<String, dynamic>();
  String get securityPatch => (raw['security_patch'] ?? '') as String;
  String get androidRelease => (raw['android_release'] ?? '') as String;
  int? get nextAlarmMillis => raw['next_alarm'] as int?;
  bool get alarmsMuted => _b('alarms_muted');

  /// Pairing mode state (see docs/PAIRING.md); null while it is off.
  Map<String, dynamic>? get pairing =>
      (raw['pairing'] as Map?)?.cast<String, dynamic>();

  /// Companion app watchdog: `enabled`, `state` (off | ok | idle | no_accessibility | unresponsive | restarting |
  /// gave_up), `responsive`, `restarts`, `last_reason`, `last_restart_at`.
  Map<String, dynamic> get watchdog =>
      Map<String, dynamic>.from((raw['watchdog'] as Map?) ?? const {});
  Map<String, dynamic>? get network =>
      (raw['network'] as Map?)?.cast<String, dynamic>();

  /// Epoch ms when the mute ends; null = until unmuted (or not muted).
  int? get alarmsMutedUntil => raw['alarms_muted_until'] as int?;
  List<TimerSpec> get timers => [
    for (final e in (raw['timers'] as List? ?? const []))
      TimerSpec.fromMap(e as Map),
  ];
}

/// A countdown ("batch 1") or count-up on the tablet. Times are absolute so the UI can tick without polling.
class TimerSpec {
  const TimerSpec({
    required this.id,
    required this.label,
    required this.kind,
    required this.state,
    required this.durationMs,
    required this.elapsedMs,
    required this.remainingMs,
    this.endsAt,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String label;

  /// `countdown` or `countup`.
  final String kind;

  /// `running`, `paused` or `finished`.
  final String state;
  final int durationMs;
  final int elapsedMs;
  final int remainingMs;
  final int? endsAt;
  final int? startedAt;

  /// Epoch ms when a countdown reached zero (finished timers only).
  final int? finishedAt;

  /// How long a finished countdown has been over.
  Duration overtime(DateTime now) => Duration(
    milliseconds: finishedAt == null
        ? 0
        : (now.millisecondsSinceEpoch - finishedAt!).clamp(0, 1 << 40),
  );

  bool get isCountdown => kind == 'countdown';
  bool get running => state == 'running';
  bool get paused => state == 'paused';
  bool get finished => state == 'finished';

  /// What the timer shows right now: time left for a countdown, time elapsed for a count-up.
  Duration shown(DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    if (isCountdown) {
      if (running && endsAt != null) {
        return Duration(milliseconds: (endsAt! - ms).clamp(0, durationMs));
      }
      return Duration(milliseconds: finished ? 0 : remainingMs);
    }
    if (running && startedAt != null) {
      return Duration(milliseconds: (ms - startedAt!).clamp(0, 1 << 40));
    }
    return Duration(milliseconds: elapsedMs);
  }

  factory TimerSpec.fromMap(Map<dynamic, dynamic> m) => TimerSpec(
    id: m['id'] as String,
    label: (m['label'] ?? '') as String,
    kind: (m['kind'] ?? 'countdown') as String,
    state: (m['state'] ?? 'running') as String,
    durationMs: ((m['duration_ms'] ?? 0) as num).toInt(),
    elapsedMs: ((m['elapsed_ms'] ?? 0) as num).toInt(),
    remainingMs: ((m['remaining_ms'] ?? 0) as num).toInt(),
    endsAt: (m['ends_at'] as num?)?.toInt(),
    startedAt: (m['started_at'] as num?)?.toInt(),
    finishedAt: (m['finished_at'] as num?)?.toInt(),
  );
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
    this.skipNext = false,
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

  /// Repeating alarm that will not ring on its next occurrence.
  final bool skipNext;
  final int? next;

  factory AlarmSpec.fromMap(Map<dynamic, dynamic> m) => AlarmSpec(
    id: m['id'] as String,
    hour: m['hour'] as int,
    minute: m['minute'] as int,
    days: ((m['days'] as List?) ?? const []).cast<int>(),
    label: (m['label'] ?? '') as String,
    enabled: (m['enabled'] ?? true) as bool,
    snoozeMinutes: (m['snooze_minutes'] ?? 9) as int,
    skipNext: (m['skip_next'] ?? false) as bool,
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
    'skip_next': skipNext,
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

  // Display / presence (brightness controller runs natively; see BrightnessController.kt)
  /// Returns the full resulting config; throws PlatformException(invalid_value) for rejected values.
  Future<Map<String, dynamic>> setDisplayConfig(Map<String, dynamic> config);
  Future<void> setExternalPresence(bool present);
  Future<void> setExternalNight(bool? night);

  /// PIN check for the Flutter PIN page. @return 0 = correct (lockdown is ended), -1 = wrong, >0 = locked out, ms remaining.
  Future<int> unlockWithPin(String pin);

  /// Closes the Android activity hosting [route] (`/pin`, `/alarm`, `/glance`) if it is the one in front.
  Future<void> closeUi(String route);

  /// Counts as a touch for dimming / idle timers (the idle screen reports taps this way).
  Future<void> reportTouch();

  // At-a-glance screen and permissions
  Future<void> setGlanceItems(List<Map<String, dynamic>> items);
  Future<bool> showGlance();
  Future<void> hideGlance();
  Future<void> requestPermission(String name);

  // Alarms
  Future<List<AlarmSpec>> getAlarms();
  Future<void> upsertAlarm(AlarmSpec alarm);
  Future<void> removeAlarm(String id);
  Future<void> stopAlarm();
  Future<void> snoozeAlarm();
  Future<void> setAlarmEnabled(String id, bool enabled);

  /// Repeating alarm: skip its next occurrence (again to undo); one-shot: disable. [id] null = the next alarm.
  Future<void> skipNextAlarm(String? id);

  /// Silences alarms until [until] / [forever]; neither unmutes. Muted alarms do not ring but keep their schedule.
  Future<void> setAlarmsMuted({DateTime? until, bool forever = false});

  /// Restart requested by Home Assistant (the dashboard beacon went silent). Returns `{healed, why?}`; refused while the
  /// screen is off, an alarm rings, the PIN pad is open, the app is not in front, or the restart limit is reached.
  Future<Map<String, dynamic>> healDashboard(String reason);

  /// Restarts the Home Assistant companion app now (device owner: hide + unhide; otherwise relaunch).
  Future<void> restartCompanion();

  // Pairing with Home Assistant: the tablet listens and advertises itself while this is on.
  Future<Map<String, dynamic>> startPairing();
  Future<void> stopPairing();

  /// Answer to a confirm-mode request shown on the tablet.
  Future<void> answerPairing(bool allow);

  // Voice (Assist satellite): microphone frames arrive as `voice_frame` platform events.
  /// Starts recording for [session]. Returns null, or an error code: `mic_permission`, `mic_busy`, `mic_failed`.
  Future<String?> voiceStart(String session);
  Future<void> voiceStop();

  /// Plays [url] and completes when it ended: null if it played to the end, else an error code.
  Future<String?> voicePlay(String url);
  Future<void> voiceStopPlayback();
  Future<void> requestMicPermission();

  /// Queues the download of the model for the wake word [id] (progress shows in the status).
  Future<void> downloadWakeWord(String id);

  /// Deletes the model of [id] and takes it out of the chosen wake words.
  Future<void> removeWakeWord(String id);

  /// Brings the full-screen page [route] (for example `/voice`) to the front.
  Future<bool> showUi(String route);

  // Timers and stopwatches
  Future<List<TimerSpec>> getTimers();

  /// Starts or restarts [id]. [kind] `countdown` needs [duration]; `countup` ignores it.
  Future<void> startTimer({
    required String id,
    String label = '',
    String kind = 'countdown',
    Duration duration = Duration.zero,
  });
  Future<void> pauseTimer(String id);
  Future<void> resumeTimer(String id);
  Future<void> cancelTimer(String id);

  /// Adds (or with a negative value removes) time on a countdown.
  Future<void> adjustTimer(String id, Duration delta);

  // System
  Future<void> startKeepAlive();
  Future<bool> openSettings(String kind);

  /// Opens the system update screen and taps through it (accessibility service required).
  Future<void> runSystemUpdate();
  Future<void> installSystemUpdate(String uri);
  Future<void> reboot();
}
