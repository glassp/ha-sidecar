import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/settings/connection_settings.dart';

void main() {
  test('websocket uri from http url', () {
    const s = ConnectionSettings(haUrl: 'http://ha.local:8123/', token: 't');
    expect(s.websocketUri.toString(), 'ws://ha.local:8123/api/ha_sidecar/ws');
  });

  test('websocket uri from https url keeps sub path', () {
    const s = ConnectionSettings(haUrl: 'https://example.org/ha', token: 't');
    expect(s.websocketUri.toString(), 'wss://example.org/ha/api/ha_sidecar/ws');
  });

  test('alarm spec round trip', () {
    const a = AlarmSpec(id: '1', hour: 6, minute: 30, days: [1, 2, 3], label: 'Work');
    final b = AlarmSpec.fromMap(a.toMap());
    expect(b.hour, 6);
    expect(b.days, [1, 2, 3]);
    expect(b.label, 'Work');
  });
}
