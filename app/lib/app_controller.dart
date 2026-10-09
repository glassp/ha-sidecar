import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ha/command_handler.dart';
import 'ha/sidecar_client.dart';
import 'platform/android_kiosk_platform.dart';
import 'platform/kiosk_platform.dart';
import 'settings/connection_settings.dart';

/// Wires platform <-> HA client and exposes UI state.
class AppController extends ChangeNotifier {
  AppController({KioskPlatform? platform})
    : platform = platform ?? AndroidKioskPlatform();

  final KioskPlatform platform;

  ConnectionSettings settings = const ConnectionSettings();
  DeviceStatus status = DeviceStatus.empty;
  List<AlarmSpec> alarms = const [];
  SidecarClient? _client;
  StreamSubscription<PlatformEvent>? _events;
  Timer? _poll;
  bool ready = false;

  /// Set by the router: navigate to a path / follow the Android activity that is in front.
  void Function(String path)? onNavigate;
  void Function(String route)? onUiRoute;

  /// First-run wizard state. `kiosk` = wall display, `extras` = sensors and alarms only.
  bool setupDone = false;
  String setupMode = 'kiosk';

  /// Events worth surfacing to HA as `ha_sidecar_event` bus events.
  static const _forwarded = {
    'alarm_ringing',
    'alarm_stopped',
    'system_update_pending',
    'system_update_install_error',
    'update_automation_started',
    'update_automation_step',
    'update_automation_finished',
    'lockdown_disabled_by_pin',
    'app_blocked',
    'pin_failed',
    'guard_disabled',
    'device_admin_disabled',
  };

  ValueListenable<LinkState>? get link => _client?.link;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    setupDone = prefs.getBool('setup_done') ?? false;
    setupMode = prefs.getString('setup_mode') ?? 'kiosk';
    settings = await ConnectionSettings.load();
    await refresh();
    _events = platform.events.listen(_onPlatformEvent);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    await platform.startKeepAlive();
    if (settings.isPaired) _startClient();
    ready = true;
    notifyListeners();
  }

  Future<void> completeSetup() async {
    setupDone = true;
    await (await SharedPreferences.getInstance()).setBool('setup_done', true);
    notifyListeners();
    onNavigate?.call('/');
  }

  Future<void> setSetupMode(String mode) async {
    setupMode = mode;
    await (await SharedPreferences.getInstance()).setString('setup_mode', mode);
    notifyListeners();
  }

  Future<void> restartSetup() async {
    setupDone = false;
    await (await SharedPreferences.getInstance()).setBool('setup_done', false);
    notifyListeners();
    onNavigate?.call('/wizard');
  }

  /// Writes one display/kiosk setting. @return a human readable error, or null on success.
  Future<String?> setConfig(String key, Object value) async {
    try {
      await platform.setDisplayConfig({key: value});
      await refresh();
      return null;
    } on PlatformException catch (e) {
      return e.code == 'invalid_value'
          ? 'That value is not valid.'
          : (e.message ?? e.code);
    }
  }

  Future<void> pair(String haUrl, String token) async {
    settings = ConnectionSettings(haUrl: haUrl, token: token);
    await settings.save();
    await _client?.stop();
    _startClient();
    notifyListeners();
  }

  Future<void> unpair() async {
    await _client?.stop();
    _client = null;
    await ConnectionSettings.clear();
    settings = const ConnectionSettings();
    notifyListeners();
  }

  void _startClient() {
    _client = SidecarClient(
      settings: settings,
      deviceInfo: () => {
        'manufacturer': status.raw['manufacturer'],
        'model': status.raw['model'],
        'android': status.androidRelease,
        'sdk': status.raw['sdk'],
      },
      onCommand: (command, data) async {
        final result = await CommandRouter(platform).handle(command, data);
        unawaited(
          refresh(),
        ); // answer HA first: a slow status read must not time the command out
        return result;
      },
      onConnected: _pushState,
    )..start();
    notifyListeners();
  }

  Future<void> refresh() async {
    status = await platform.getStatus();
    alarms = await platform.getAlarms();
    notifyListeners();
    await _pushState();
  }

  Future<void> _pushState() async => _client?.sendState(status.raw);

  Future<void> _onPlatformEvent(PlatformEvent e) async {
    if (e.type == 'ui_route') {
      onUiRoute?.call(e.data['route'] as String);
      return;
    }
    if (e.type == 'alarm_stopped') await platform.closeUi('/alarm');
    await refresh();
    if (_forwarded.contains(e.type)) _client?.sendEvent(e.type, e.data);
  }

  @override
  void dispose() {
    _events?.cancel();
    _poll?.cancel();
    _client?.stop();
    super.dispose();
  }
}
