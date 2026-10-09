import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/voice/voice_controller.dart';

class FakePlatform extends Fake implements KioskPlatform {
  String? startError;
  final played = <String>[];
  final calls = <String>[];
  Completer<String?>?
  playGate; // hold a playback open until the test completes it

  @override
  Future<String?> voiceStart(String session) async {
    calls.add('start:$session');
    return startError;
  }

  @override
  Future<void> voiceStop() async => calls.add('stop');

  @override
  Future<String?> voicePlay(String url) async {
    played.add(url);
    return playGate == null ? null : await playGate!.future;
  }

  @override
  Future<void> voiceStopPlayback() async => calls.add('stopPlayback');

  @override
  Future<bool> showUi(String route) async {
    calls.add('show:$route');
    return true;
  }

  @override
  Future<void> closeUi(String route) async => calls.add('close:$route');
}

void main() {
  late FakePlatform platform;
  late List<Map<String, dynamic>> sent;
  late bool connected;
  late VoiceController v;

  setUp(() {
    platform = FakePlatform();
    sent = [];
    connected = true;
    v = VoiceController(
      platform: platform,
      send: (m) {
        if (!connected) return false;
        sent.add(m);
        return true;
      },
      baseUrl: () => connected ? 'http://ha.local:8123' : null,
      dismissAfter: const Duration(milliseconds: 50),
      silenceTimeout: const Duration(milliseconds: 300),
    );
  });
  tearDown(() => v.dispose());

  List<String> actions() => [for (final m in sent) m['action'] as String];
  Map<String, dynamic> hae(
    String event, [
    Map<String, dynamic> data = const {},
  ]) => {
    'type': 'voice_event',
    'session': v.session,
    'event': event,
    'data': data,
  };

  test(
    'a full turn: start, frames, stt-end stops recording, answer is played, played is reported',
    () async {
      expect(await v.listen(), isNull);
      expect(v.state, VoiceState.listening);
      expect(actions(), ['start']);
      v.onPlatformEvent(
        PlatformEvent('voice_frame', {
          'session': v.session,
          'data': 'AAAA',
          'level': 0.4,
        }),
      );
      expect(actions(), ['start', 'audio']);
      expect(v.level, 0.4);

      v.onVoiceEvent(hae('stt-end', {'text': 'what time is it'}));
      await Future<void>.delayed(Duration.zero);
      expect(v.transcript, 'what time is it');
      expect(v.state, VoiceState.thinking);
      expect(platform.calls, contains('stop'));
      expect(actions().last, 'stop');

      v.onVoiceEvent(hae('intent-end', {'text': 'It is noon.'}));
      expect(v.answer, 'It is noon.');
      v.onVoiceEvent(hae('tts-end', {'url': '/api/tts_proxy/x.mp3'}));
      await Future<void>.delayed(Duration.zero);
      expect(platform.played, ['http://ha.local:8123/api/tts_proxy/x.mp3']);
      expect(actions().last, 'played');
      expect(v.state, VoiceState.idle);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(platform.calls.last, 'close:/voice');
    },
  );

  test(
    'the answer is fetched through the address we are connected through, not the one Home Assistant names',
    () async {
      await v.listen();
      v.onVoiceEvent(
        hae('tts-end', {
          'url': 'http://192.168.1.5:8123/api/tts_proxy/y.mp3?authSig=abc',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(platform.played, [
        'http://ha.local:8123/api/tts_proxy/y.mp3?authSig=abc',
      ]);
    },
  );

  test(
    'microphone errors are reported, the turn is cancelled towards Home Assistant and the page closes',
    () async {
      platform.startError = 'mic_permission';
      expect(await v.listen(), 'mic_permission');
      expect(v.state, VoiceState.error);
      expect(v.errorCode, 'mic_permission');
      expect(actions(), ['start', 'cancel']);
    },
  );

  test('not connected: no start, an error the UI can show', () async {
    connected = false;
    expect(await v.listen(), 'not_connected');
    expect(v.state, VoiceState.error);
    expect(platform.calls.where((c) => c.startsWith('start')), isEmpty);
  });

  test('events of another (cancelled) turn are ignored', () async {
    await v.listen();
    v.onVoiceEvent({
      'type': 'voice_event',
      'session': 'old',
      'event': 'stt-end',
      'data': {'text': 'stale'},
    });
    expect(v.transcript, '');
    expect(v.state, VoiceState.listening);
    v.onPlatformEvent(
      PlatformEvent('voice_frame', {
        'session': 'old',
        'data': 'AAAA',
        'level': 1,
      }),
    );
    expect(actions(), ['start']);
  });

  test('barge-in: a second listen cancels the first turn', () async {
    await v.listen();
    final first = v.session;
    await v.listen();
    expect(v.session, isNot(first));
    expect(actions(), ['start', 'cancel', 'start']);
  });

  test(
    'a Home Assistant error ends the turn with its code and message',
    () async {
      await v.listen();
      v.onVoiceEvent(
        hae('error', {
          'code': 'stt-no-text-recognized',
          'message': 'no speech',
        }),
      );
      expect(v.state, VoiceState.error);
      expect(v.errorCode, 'stt-no-text-recognized');
      expect(v.errorMessage, 'no speech');
    },
  );

  test('a run that ends without speaking finishes the turn', () async {
    await v.listen();
    v.onVoiceEvent(hae('run-end'));
    expect(v.state, VoiceState.idle);
  });

  test('no answer in time: timeout error and the turn is cancelled', () async {
    await v.listen();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(v.state, VoiceState.error);
    expect(v.errorCode, 'timeout');
    expect(actions().last, 'cancel');
  });

  test('losing the connection cancels the turn', () async {
    await v.listen();
    connected = false;
    v.onDisconnected();
    await Future<void>.delayed(Duration.zero);
    expect(v.state, VoiceState.idle);
    expect(v.session, isNull);
  });

  test(
    'cancel while the answer is spoken stops playback and does not report played',
    () async {
      platform.playGate = Completer<String?>();
      await v.listen();
      v.onVoiceEvent(hae('tts-end', {'url': '/a.mp3'}));
      await Future<void>.delayed(Duration.zero);
      expect(v.state, VoiceState.speaking);
      await v.cancel();
      platform.playGate!.complete('interrupted');
      await Future<void>.delayed(Duration.zero);
      expect(actions(), isNot(contains('played')));
      expect(platform.calls, contains('stopPlayback'));
    },
  );

  test(
    'announce plays the pre-announce sound and then the announcement, in order, and completes when both ended',
    () async {
      await v.announce(
        url: '/api/tts_proxy/a.mp3',
        message: 'Dinner',
        preannounceUrl: '/api/assist_satellite/static/preannounce.mp3',
      );
      expect(platform.played, [
        'http://ha.local:8123/api/assist_satellite/static/preannounce.mp3',
        'http://ha.local:8123/api/tts_proxy/a.mp3',
      ]);
      expect(v.answer, 'Dinner');
      expect(v.state, VoiceState.idle);
    },
  );

  test('announce reports a playback error to the caller', () async {
    platform.playGate = Completer<String?>()..complete('playback_error:1/2');
    await expectLater(v.announce(url: '/a.mp3'), throwsStateError);
    expect(v.state, VoiceState.idle);
  });
}
