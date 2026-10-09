import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum LinkState { disconnected, connecting, connected, authFailed }

class CommandException implements Exception {
  CommandException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'CommandException($code, $message)';
}

typedef CommandHandler =
    Future<Map<String, dynamic>?> Function(
      String command,
      Map<String, dynamic> data,
    );

/// Outbound WebSocket to the `ha_sidecar` integration (see docs/PROTOCOL.md).
/// The tablet connects out, so no port has to be opened on the device.
class SidecarClient {
  SidecarClient({
    required this.uri,
    required this.token,
    required this.deviceInfo,
    required this.onCommand,
    required this.onConnected,
  });

  /// WebSocket address (internal or external, chosen by the connection policy) and the pairing token.
  final Uri uri;
  final String token;
  final Map<String, dynamic> Function() deviceInfo;
  final CommandHandler onCommand;

  /// Called after a successful handshake, so the owner can push its full state.
  final Future<void> Function() onConnected;

  final ValueNotifier<LinkState> link = ValueNotifier(LinkState.disconnected);

  WebSocketChannel? _channel;
  bool _running = false;
  int _attempt = 0;
  Timer? _retry;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    await _channel?.sink.close();
    _channel = null;
    link.value = LinkState.disconnected;
  }

  void sendState(Map<String, dynamic> state) =>
      _send({'type': 'state', 'state': state});

  void sendEvent(String event, Map<String, dynamic> data) =>
      _send({'type': 'event', 'event': event, 'data': data});

  void _send(Map<String, dynamic> msg) {
    if (link.value != LinkState.connected) return;
    _channel?.sink.add(jsonEncode(msg));
  }

  Future<void> _connect() async {
    if (!_running) return;
    link.value = LinkState.connecting;
    try {
      final ch = WebSocketChannel.connect(uri);
      _channel = ch;
      await ch.ready.timeout(const Duration(seconds: 10));

      ch.sink.add(
        jsonEncode({
          'type': 'hello',
          'protocol': 1,
          'token': token,
          'device': deviceInfo(),
        }),
      );
      final done = Completer<void>();
      var authenticated = false;

      ch.stream.listen(
        (raw) async {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          switch (msg['type']) {
            case 'hello_ok':
              authenticated = true;
              _attempt = 0;
              link.value = LinkState.connected;
              await onConnected();
            case 'auth_failed':
              link.value = LinkState.authFailed;
              _running =
                  false; // retrying with a wrong token only spams the server
              await ch.sink.close();
            case 'command':
              await _handleCommand(msg);
          }
        },
        onDone: () => done.complete(),
        onError: (_) => done.complete(),
        cancelOnError: true,
      );
      await done.future;
      if (!authenticated && link.value != LinkState.authFailed) {
        debugPrint('SidecarClient: closed before handshake completed');
      }
    } catch (e) {
      debugPrint('SidecarClient: connect failed: $e');
    }
    if (link.value != LinkState.authFailed) link.value = LinkState.disconnected;
    _scheduleRetry();
  }

  Future<void> _handleCommand(Map<String, dynamic> msg) async {
    final id = msg['id'];
    try {
      final data = await onCommand(
        msg['command'] as String,
        Map<String, dynamic>.from((msg['data'] as Map?) ?? const {}),
      );
      _send({
        'type': 'result',
        'id': id,
        'success': true,
        'data': data ?? const {},
      });
    } on CommandException catch (e) {
      _send({
        'type': 'result',
        'id': id,
        'success': false,
        'error': e.code,
        'message': e.message,
      });
    } catch (e) {
      _send({
        'type': 'result',
        'id': id,
        'success': false,
        'error': 'exception',
        'message': '$e',
      });
    }
  }

  void _scheduleRetry() {
    if (!_running) return;
    final seconds = (1 << _attempt.clamp(0, 5)).clamp(1, 30); // 1,2,4,8,16,30
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), _connect);
  }
}
