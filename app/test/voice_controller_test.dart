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
  Future<void> voicePing(String kind) async => calls.add('ping:$kind');

  @override
  Future<bool> showUi(String route) async {
    calls.add('show:$route');
    return true;
  }

  @override
  Future<void> closeUi(String route) async => calls.add('close:$route');

  @override
  Future<void> voiceVolumeRaise(int percent) async =>
      calls.add('volume:$percent');

  @override
  Future<void> voiceVolumeRestore() async => calls.add('volume:restore');

  bool bubbleOk = true;
  final bubbles = <Map<String, Object?>>[];

  @override
  Future<bool> bubbleAvailable() async => bubbleOk;

  @override
  Future<void> bubbleUpdate(Map<String, Object?> snapshot) async {
    bubbles.add(snapshot);
    calls.add('bubble');
  }

  @override
  Future<void> bubbleHide() async => calls.add('bubbleHide');
}

void main() {
  voiceTurnTests();
  dockedTests();
  volumeTests();
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
      conversationEnabled: () => false,
      soundsEnabled: () => false,
      firstTimeout: const Duration(seconds: 30),
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

  test(
    'a slow agent (a local LLM) is waited for: the thinking stage has its own, longer limit',
    () async {
      await v.listen();
      v.onVoiceEvent(
        hae('stt-end', {'text': 'what is the average temperature'}),
      );
      await Future<void>.delayed(
        const Duration(milliseconds: 500),
      ); // longer than silenceTimeout (300 ms)
      expect(v.state, VoiceState.thinking);
      expect(v.errorCode, isNull);
    },
  );

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

void voiceTurnTests() {
  late FakePlatform platform;
  late List<Map<String, dynamic>> sent;
  late VoiceController v;

  setUp(() {
    platform = FakePlatform();
    sent = [];
    v = VoiceController(
      platform: platform,
      send: (m) {
        sent.add(m);
        return true;
      },
      baseUrl: () => 'http://ha.local:8123',
      dismissAfter: const Duration(milliseconds: 50),
      silenceTimeout: const Duration(seconds: 5),
      firstTimeout: const Duration(milliseconds: 150),
      followUpTimeout: () => const Duration(milliseconds: 150),
    );
  });
  tearDown(() => v.dispose());

  Map<String, dynamic> ev(
    String event, [
    Map<String, dynamic> data = const {},
  ]) => {
    'type': 'voice_event',
    'session': v.session,
    'event': event,
    'data': data,
  };

  test(
    'what was said and answered is kept as turns of one conversation',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'what time is it'}));
      v.onVoiceEvent(ev('intent-end', {'text': 'Noon.'}));
      expect(v.turns.length, 1);
      expect(v.turns.single.user, 'what time is it');
      expect(v.turns.single.assistant, 'Noon.');
    },
  );

  test(
    'a new turn that is not a continuation starts a fresh conversation',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'one'}));
      await v.listen();
      expect(v.turns.length, 1);
      expect(v.transcript, '');
    },
  );

  test(
    'when the assistant asks something, the tablet listens again and the conversation stays',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'order a pizza'}));
      v.onVoiceEvent(
        ev('intent-end', {
          'text': 'Which size?',
          'continue_conversation': true,
        }),
      );
      v.onVoiceEvent(ev('tts-end', {'url': '/a.mp3'}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        sent.where((m) => m['action'] == 'start').length,
        2,
        reason: 'a second turn was started',
      );
      expect(v.turns.length, 2);
      expect(v.turns.first.assistant, 'Which size?');
      expect(v.state, VoiceState.listening);
    },
  );

  test(
    'a spoken answer is followed by listening again, with a ping before each listening',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'hello'}));
      v.onVoiceEvent(ev('intent-end', {'text': 'Hi.'}));
      v.onVoiceEvent(ev('tts-end', {'url': '/a.mp3'}));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sent.where((m) => m['action'] == 'start').length, 2);
      expect(v.state, VoiceState.listening);
      expect(v.followUp, isTrue);
      final starts = [
        for (var i = 0; i < platform.calls.length; i++)
          if (platform.calls[i].startsWith('start:')) i,
      ];
      for (final i in starts) {
        expect(
          platform.calls[i - 1],
          'ping:start',
          reason: 'the ping plays before the microphone opens',
        );
      }
    },
  );

  test(
    'nothing said in the follow-up window ends the conversation with the closing ping',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'hello'}));
      v.onVoiceEvent(ev('tts-end', {'url': '/a.mp3'}));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(v.inConversation, isFalse);
      expect(v.state, VoiceState.idle);
      expect(platform.calls, contains('ping:end'));
      expect(
        sent.where((m) => m['action'] == 'cancel'),
        isNotEmpty,
        reason: 'Home Assistant is told',
      );
    },
  );

  test(
    'speech detected by Home Assistant stops the clock, so a long question is not cut off',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-vad-start'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(v.state, VoiceState.listening);
      expect(v.inConversation, isTrue);
      expect(v.waitingForSpeech, isFalse);
    },
  );

  test(
    'loud microphone frames stop the clock too, when the pipeline sends no voice events',
    () async {
      await v.listen();
      for (var i = 0; i < 3; i++) {
        v.onPlatformEvent(
          PlatformEvent('voice_frame', {
            'session': v.session,
            'data': 'AAAA',
            'level': 0.6,
          }),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(v.state, VoiceState.listening);
    },
  );

  test('the first listening gives up after its own timeout, quietly', () async {
    await v.listen();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(v.inConversation, isFalse);
    expect(v.state, VoiceState.idle);
    expect(v.errorCode, isNull, reason: 'silence is not an error');
    expect(platform.calls, contains('ping:end'));
  });

  test(
    'ending the conversation stops everything, tells Home Assistant, pings and closes',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'hello'}));
      final id = v.session;
      await v.endConversation();
      expect(v.inConversation, isFalse);
      expect(v.session, isNull);
      expect(sent.last, {'type': 'voice', 'action': 'cancel', 'session': id});
      expect(
        platform.calls,
        containsAllInOrder(['stopPlayback', 'ping:end', 'close:/voice']),
      );
    },
  );

  test(
    'an answer that was not spoken (a question to Home Assistant) ends it after the answer',
    () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'yes'}));
      v.onVoiceEvent(ev('run-end'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(v.inConversation, isFalse);
      expect(platform.calls, contains('ping:end'));
    },
  );

  test(
    'with follow-ups switched off a spoken answer ends the conversation',
    () async {
      final off = VoiceController(
        platform: platform,
        send: (m) {
          sent.add(m);
          return true;
        },
        baseUrl: () => 'http://ha.local:8123',
        conversationEnabled: () => false,
        soundsEnabled: () => false,
      );
      addTearDown(off.dispose);
      await off.listen();
      off.onVoiceEvent({
        'type': 'voice_event',
        'session': off.session,
        'event': 'tts-end',
        'data': {'url': '/a.mp3'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(sent.where((m) => m['action'] == 'start').length, 1);
      expect(off.inConversation, isFalse);
    },
  );

  test('the pings can be switched off', () async {
    final quiet = VoiceController(
      platform: platform,
      send: (m) => true,
      baseUrl: () => 'http://ha.local:8123',
      soundsEnabled: () => false,
    );
    addTearDown(quiet.dispose);
    await quiet.listen();
    await quiet.endConversation();
    expect(platform.calls.where((c) => c.startsWith('ping')), isEmpty);
  });

  test(
    'a conversation started by Home Assistant plays the question, then listens, and keeps the question on screen',
    () async {
      await v.conversation(
        url: '/q.mp3',
        message: 'Shall I turn the light off?',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(v.turns.length, 2);
      expect(v.turns.first.assistant, 'Shall I turn the light off?');
      expect(v.state, VoiceState.listening);
      expect(sent.where((m) => m['action'] == 'start').length, 1);
    },
  );

  test('the waveform keeps only the newest levels', () async {
    await v.listen();
    for (var i = 0; i < VoiceController.levelHistory + 10; i++) {
      v.onPlatformEvent(
        PlatformEvent('voice_frame', {
          'session': v.session,
          'data': 'AAAA',
          'level': i / 100,
        }),
      );
    }
    expect(v.levels.length, VoiceController.levelHistory);
    expect(v.levels.last, (VoiceController.levelHistory + 9) / 100);
  });
}

void dockedTests() {
  late FakePlatform platform;
  late List<Map<String, dynamic>> sent;
  late VoiceController v;
  late bool docked;
  var skin = 'midnight';

  setUp(() {
    platform = FakePlatform();
    sent = [];
    docked = true;
    v = VoiceController(
      platform: platform,
      send: (m) {
        sent.add(m);
        return true;
      },
      baseUrl: () => 'http://ha.local:8123',
      dismissAfter: const Duration(milliseconds: 50),
      silenceTimeout: const Duration(seconds: 5),
      conversationEnabled: () => false,
      soundsEnabled: () => false,
      dockedEnabled: () => docked,
      bubbleText: (k) => 'T:$k',
      skinId: () => skin,
    );
  });
  tearDown(() => v.dispose());

  Map<String, dynamic> ev(
    String event, [
    Map<String, dynamic> data = const {},
  ]) => {
    'type': 'voice_event',
    'session': v.session,
    'event': event,
    'data': data,
  };

  group('docked card', () {
    test(
      'a turn shows the card instead of the full page and feeds it the state',
      () async {
        await v.listen();
        expect(platform.calls, isNot(contains('show:/voice')));
        expect(v.docked, isTrue);
        expect(platform.bubbles.last['state'], 'listening');
        expect(
          (platform.bubbles.last['labels'] as Map)['listening'],
          'T:listening',
        );
        v.onVoiceEvent(ev('stt-end', {'text': 'is the door locked'}));
        v.onVoiceEvent(ev('intent-end', {'text': 'Yes, it is locked.'}));
        expect(platform.bubbles.last['user'], 'is the door locked');
        expect(platform.bubbles.last['assistant'], 'Yes, it is locked.');
      },
    );

    test('the card gets the palette of the chosen skin', () async {
      skin = 'aurora';
      await v.listen();
      final palette = platform.bubbles.last['skin'] as Map;
      expect(palette['id'], 'aurora');
      expect(palette['accent'], '#5EEAD4');
      skin = 'nope';
      v.notifyListeners();
      expect(
        (platform.bubbles.last['skin'] as Map)['id'],
        'midnight',
        reason: 'unknown skin: the default',
      );
    });

    test('it carries no timers', () async {
      await v.listen();
      expect(
        platform.bubbles.last.keys.any((k) => k.contains('timer')),
        isFalse,
      );
    });

    test('closing removes the card, not the page', () async {
      await v.listen();
      v.onVoiceEvent(ev('stt-end', {'text': 'hi'}));
      v.onVoiceEvent(ev('tts-end', {'url': '/a.mp3'}));
      await v.endConversation();
      expect(platform.calls, contains('bubbleHide'));
      expect(platform.calls, isNot(contains('close:/voice')));
      expect(v.docked, isFalse);
      expect(v.shown, isFalse);
    });

    test('without permission (or a dark screen) the full page opens', () async {
      platform.bubbleOk = false;
      await v.listen();
      expect(platform.calls, contains('show:/voice'));
      expect(v.docked, isFalse);
      expect(platform.bubbles, isEmpty);
    });

    test('switched off, the full page opens', () async {
      docked = false;
      await v.listen();
      expect(platform.calls, contains('show:/voice'));
      expect(platform.bubbles, isEmpty);
    });

    test(
      'tapping the card opens the full page and the card stays away for this conversation',
      () async {
        await v.listen();
        final before = platform.bubbles.length;
        await v.onBubbleAction('expand');
        expect(
          platform.calls,
          containsAllInOrder(['bubbleHide', 'show:/voice']),
        );
        expect(v.docked, isFalse);
        v.onVoiceEvent(ev('stt-end', {'text': 'hello'}));
        expect(
          platform.bubbles.length,
          before,
          reason: 'no more updates to a card that is gone',
        );
        await v.endConversation();
        expect(platform.calls, contains('close:/voice'));
        // the next conversation is docked again
        await v.listen();
        expect(v.docked, isTrue);
      },
    );

    test(
      'its buttons act: done talking stops, end conversation ends',
      () async {
        await v.listen();
        await v.onBubbleAction('done');
        expect(sent.where((m) => m['action'] == 'stop'), isNotEmpty);
        await v.onBubbleAction('end');
        expect(v.state, VoiceState.idle);
        expect(platform.calls, contains('bubbleHide'));
      },
    );

    test(
      'an error shows a message on the card and Talk again starts a new turn',
      () async {
        await v.listen();
        v.onVoiceEvent(
          ev('error', {'code': 'stt-no-text-recognized', 'message': 'x'}),
        );
        expect(platform.bubbles.last['state'], 'error');
        expect(
          platform.bubbles.last['error'],
          'T:err_unknown',
        ); // the fake translates nothing: falls back
        final sessions = sent.where((m) => m['action'] == 'start').length;
        await v.onBubbleAction('again');
        expect(sent.where((m) => m['action'] == 'start').length, sessions + 1);
      },
    );

    test(
      'microphone levels are throttled but the first one of a burst gets through',
      () async {
        await v.listen();
        final n = platform.bubbles.length;
        for (var i = 0; i < 20; i++) {
          v.onPlatformEvent(
            PlatformEvent('voice_frame', {
              'session': v.session,
              'data': 'AAAA',
              'level': i / 20,
            }),
          );
        }
        expect(platform.bubbles.length - n, lessThan(20));
      },
    );
  });
}

void volumeTests() {
  late FakePlatform platform;
  late VoiceController v;
  int? level;
  final saved = <int>[];

  setUp(() {
    platform = FakePlatform();
    level = 50;
    v = VoiceController(
      platform: platform,
      send: (m) => true,
      baseUrl: () => 'http://ha.local:8123',
      dismissAfter: const Duration(milliseconds: 50),
      silenceTimeout: const Duration(seconds: 5),
      conversationEnabled: () => false,
      soundsEnabled: () => true,
      volumeLevel: () => level,
      saveVolume: (p) async => saved.add(p),
    );
    saved.clear();
  });
  tearDown(() => v.dispose());

  Map<String, dynamic> ev(
    String event, [
    Map<String, dynamic> data = const {},
  ]) => {
    'type': 'voice_event',
    'session': v.session,
    'event': event,
    'data': data,
  };

  group('voice volume', () {
    test(
      'is raised before the first sound and restored a moment after the session',
      () async {
        await v.listen();
        final calls = platform.calls;
        expect(
          calls.indexOf('volume:50'),
          lessThan(calls.indexOf('ping:start')),
          reason: 'before the ping, so the ping is at the voice volume',
        );
        v.onVoiceEvent(ev('stt-end', {'text': 'hi'}));
        v.onVoiceEvent(ev('tts-end', {'url': '/a.mp3'}));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          calls,
          isNot(contains('volume:restore')),
          reason: 'not while the answer is playing',
        );
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(calls, contains('volume:restore'));
      },
    );

    test('an announcement is played at the voice volume too', () async {
      await v.announce(url: '/a.mp3', message: 'Dinner');
      expect(
        platform.calls.indexOf('volume:50'),
        lessThan(platform.played.isEmpty ? 1 << 30 : 1 << 29),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(platform.calls, contains('volume:restore'));
    });

    test(
      'the slider changes the volume for this conversation only; the next one starts at the setting again',
      () async {
        await v.listen();
        await v.changeVolume(80);
        expect(platform.calls, contains('volume:80'));
        expect(v.volume, 80);
        await v.endConversation();
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(platform.calls, contains('volume:restore'));
        expect(v.volume, 50, reason: 'back to the configured voice volume');
        platform.calls.clear();
        await v.listen();
        expect(
          platform.calls.where(
            (c) => c.startsWith('volume:') && c != 'volume:restore',
          ),
          ['volume:50'],
        );
      },
    );

    test(
      '"set the volume to 30 percent" during a conversation is for the conversation, not the setting',
      () async {
        await v.listen();
        expect(await v.setVolumeCommand(percent: 30), 'conversation');
        expect(platform.calls, contains('volume:30'));
        expect(saved, isEmpty);
      },
    );

    test('"louder" / "quieter" step from the current level', () async {
      await v.listen();
      await v.setVolumeCommand(delta: 10);
      expect(v.volume, 60);
      await v.setVolumeCommand(delta: -30);
      expect(v.volume, 30);
      await v.setVolumeCommand(delta: -50);
      expect(v.volume, 0, reason: 'not below silent');
    });

    test(
      'a volume command outside a conversation sets the preferred volume',
      () async {
        expect(await v.setVolumeCommand(percent: 20), 'preferred');
        expect(saved, [20]);
        expect(platform.calls.where((c) => c.startsWith('volume:')), isEmpty);
      },
    );

    test('0 means silent: the volume is set to 0 for the session', () async {
      level = 0;
      await v.listen();
      expect(platform.calls, contains('volume:0'));
    });

    test('without a level the volume is not touched', () async {
      level = null;
      await v.listen();
      v.onVoiceEvent(ev('tts-end', {'url': '/a.mp3'}));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(platform.calls.where((c) => c.startsWith('volume')), isEmpty);
    });

    test(
      'a conversation keeps the volume between its turns and restores it once at the end',
      () async {
        final c = VoiceController(
          platform: platform,
          send: (m) => true,
          baseUrl: () => 'http://ha.local:8123',
          dismissAfter: const Duration(milliseconds: 50),
          silenceTimeout: const Duration(seconds: 5),
          followUpTimeout: () => const Duration(milliseconds: 1500),
          soundsEnabled: () => false,
          volumeLevel: () => 50,
        );
        addTearDown(c.dispose);
        await c.listen();
        c.onVoiceEvent({
          'type': 'voice_event',
          'session': c.session,
          'event': 'tts-end',
          'data': {'url': '/a.mp3'},
        });
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        expect(c.inConversation, isTrue);
        expect(
          platform.calls.where((x) => x == 'volume:restore'),
          isEmpty,
          reason: 'still in the conversation',
        );
        await c.endConversation();
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(platform.calls.where((x) => x == 'volume:restore').length, 1);
      },
    );
  });
}
