import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ha/command_handler.dart';
import 'ha/sidecar_client.dart';
import 'platform/android_kiosk_platform.dart';
import 'platform/kiosk_platform.dart';
import 'settings/connection_route.dart';
import 'settings/connection_settings.dart';

/// Wires platform <-> HA client and exposes UI state.
class AppController extends ChangeNotifier {
  AppController({KioskPlatform? platform})
    : platform = platform ?? AndroidKioskPlatform();

  final KioskPlatform platform;

  ConnectionSettings settings = const ConnectionSettings();
  DeviceStatus status = DeviceStatus.empty;
  List<AlarmSpec> alarms = const [];
  NetworkState network = const NetworkState();

  /// Which address the persistent connection uses right now (or why there is none).
  ConnectionRoute route = const ConnectionRoute(RouteKind.offline);
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
    'companion_unresponsive',
    'companion_restarted',
    'companion_restart_gave_up',
    'alarm_skipped',
    'alarms_muted',
    'alarms_unmuted',
    'timer_started',
    'timer_paused',
    'timer_resumed',
    'timer_cancelled',
    'timer_extended',
    'timer_finished',
    'timer_snoozed',
    'timer_dismissed',
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
    status = await platform.getStatus();
    network = NetworkState.fromMap(status.network);
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

  Future<void> pair(String haUrl, String token, {String? externalUrl}) async {
    settings = settings.copyWith(
      haUrl: haUrl,
      token: token,
      externalUrl: externalUrl ?? settings.externalUrl,
    );
    await settings.save();
    await _restartClient();
  }

  /// Saves changed connection options (addresses, home networks, policy) and re-evaluates which address to use.
  Future<void> updateConnection(ConnectionSettings next) async {
    settings = next;
    await settings.save();
    await _restartClient();
  }

  Future<void> _restartClient() async {
    await _client?.stop();
    _client = null;
    _startClient();
    notifyListeners();
  }

  /// A completed pairing hands over the token and the address(es) of Home Assistant.
  Future<void> _onPaired(Map<String, dynamic> d) async {
    final internal = (d['internal_url'] as String?) ?? '';
    final external = (d['external_url'] as String?) ?? '';
    final ssid = network.ssid;
    settings = settings.copyWith(
      homeSsids:
          ssid != null &&
              internal.isNotEmpty &&
              !settings.homeSsids.contains(ssid)
          ? [...settings.homeSsids, ssid]
          : null,
    );
    await pair(
      internal.isNotEmpty ? internal : external,
      d['token'] as String,
      externalUrl: internal.isNotEmpty ? external : '',
    );
  }

  Future<void> unpair() async {
    await _client?.stop();
    _client = null;
    await ConnectionSettings.clear();
    settings = settings.copyWith(haUrl: '', token: '', externalUrl: '');
    notifyListeners();
  }

  void _startClient() {
    route = chooseRoute(settings, network);
    final url = route.url;
    if (!settings.isPaired || url == null || url.isEmpty) {
      _client = null;
      return;
    }
    _client = SidecarClient(
      uri: ConnectionSettings.websocketUriFor(url),
      token: settings.token,
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
    final net = NetworkState.fromMap(status.network);
    final networkChanged = !_sameNetwork(net, network);
    network = net;
    if (networkChanged && settings.isPaired && ready) {
      final next = chooseRoute(settings, network);
      if (next != route) await _restartClient();
    }
    notifyListeners();
    await _pushState();
  }

  static bool _sameNetwork(NetworkState a, NetworkState b) =>
      a.connected == b.connected &&
      a.wifi == b.wifi &&
      a.ethernet == b.ethernet &&
      a.cellular == b.cellular &&
      a.vpn == b.vpn &&
      a.ssid == b.ssid;

  Future<void> _pushState() async => _client?.sendState(status.raw);

  Future<void> _onPlatformEvent(PlatformEvent e) async {
    if (e.type == 'ui_route') {
      onUiRoute?.call(e.data['route'] as String);
      return;
    }
    if (e.type == 'paired') {
      await _onPaired(e.data);
      return;
    }
    if (e.type == 'ring_ended') await platform.closeUi('/alarm');
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
