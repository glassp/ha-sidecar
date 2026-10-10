import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/ha/sidecar_client.dart';

SidecarClient _client(Uri uri) => SidecarClient(
  uri: uri,
  token: 't',
  deviceInfo: () => const {},
  onCommand: (_, _) async => null,
  onConnected: () async {},
);

void main() {
  // A server that answers the upgrade request with plain HTTP, like Home Assistant before the integration is set up.
  late HttpServer plain;
  setUp(() async {
    plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plain.listen((r) {
      r.response
        ..statusCode = 404
        ..close();
    });
  });
  tearDown(() => plain.close(force: true));

  test(
    'stop() returns after a failed connect (re-pairing restarts the client)',
    () async {
      final c = _client(Uri.parse('ws://127.0.0.1:${plain.port}/ws'))..start();
      await Future<void>.delayed(
        const Duration(milliseconds: 600),
      ); // first attempt has failed, retry pending
      await c.stop().timeout(const Duration(seconds: 3));
      expect(c.link.value, LinkState.disconnected);
    },
  );

  test('stop() during a connect that never completes returns too', () async {
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    silent.listen((_) {}); // accepts, never answers
    final c = _client(Uri.parse('ws://127.0.0.1:${silent.port}/ws'))..start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await c.stop().timeout(const Duration(seconds: 3));
    await silent.close();
  });

  test('a client stopped while connecting does not keep retrying', () async {
    var hits = 0;
    final counting = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    counting.listen((r) {
      hits++;
      r.response
        ..statusCode = 404
        ..close();
    });
    final c = _client(Uri.parse('ws://127.0.0.1:${counting.port}/ws'))..start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await c.stop().timeout(const Duration(seconds: 3));
    final seen = hits;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(hits, seen);
    await counting.close(force: true);
  });
  test(
    'a broken or binary frame is ignored and the next command is still answered',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final answers = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen((raw) {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          if (msg['type'] == 'hello') {
            ws.add(jsonEncode({'type': 'hello_ok'}));
            ws.add('this is {not json'); // broken JSON
            ws.add([1, 2, 3]); // a binary frame
            ws.add(jsonEncode([1, 2, 3])); // valid JSON, but not an object
            ws.add(
              jsonEncode({
                'type': 'command',
                'id': 7,
                'command': 'ping',
                'data': {},
              }),
            );
          } else if (msg['type'] == 'result' && !answers.isCompleted) {
            answers.complete(msg);
          }
        });
      });
      final c = SidecarClient(
        uri: Uri.parse('ws://127.0.0.1:${server.port}/ws'),
        token: 't',
        deviceInfo: () => const {},
        onCommand: (command, _) async => {'echo': command},
        onConnected: () async {},
      )..start();
      final result = await answers.future.timeout(const Duration(seconds: 5));
      expect(result['id'], 7);
      expect(result['success'], true);
      expect(c.link.value, LinkState.connected);
      await c.stop();
      await server.close(force: true);
    },
  );
}
