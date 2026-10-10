import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/app_controller.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/ui/pages/voice_page.dart';
import 'package:ha_sidecar/voice/voice_card.dart';
import 'package:ha_sidecar/voice/voice_controller.dart';

class FakePlatform extends Fake implements KioskPlatform {
  final calls = <String>[];
  final bubbles = <Map<String, Object?>>[];
  bool bubbleOk = false;

  @override
  Future<DeviceStatus> getStatus() async => DeviceStatus({});
  @override
  Future<List<AlarmSpec>> getAlarms() async => const [];
  @override
  Future<String?> voiceStart(String session) async => null;
  @override
  Future<void> voiceStop() async {}
  @override
  Future<void> voicePing(String kind) async {}
  @override
  Future<void> voiceStopPlayback() async {}
  @override
  Future<String?> voicePlay(String url) async => null;
  @override
  Future<bool> showUi(String route) async {
    calls.add('show:$route');
    return true;
  }

  @override
  Future<void> closeUi(String route) async => calls.add('close:$route');
  @override
  Future<bool> bubbleAvailable() async => bubbleOk;
  @override
  Future<void> bubbleUpdate(Map<String, Object?> snapshot) async =>
      bubbles.add(snapshot);
  @override
  Future<void> bubbleHide() async => calls.add('bubbleHide');
}

const weather = {
  'type': 'weather',
  'title': 'Home',
  'subtitle': 'Partly cloudy',
  'value': '21 °C',
  'icon': 'partlycloudy',
  'details': ['Humidity 60 %', 'Wind 12 km/h'],
  'forecast': [
    {'label': 'Mon', 'value': '22° / 12°', 'icon': 'sunny'},
    {'label': 'Tue', 'value': '18° / 10°', 'icon': 'rainy'},
  ],
  'entity_id': 'weather.home',
};

void main() {
  group('VoiceCard.fromJson', () {
    test('reads a weather card with its forecast', () {
      final c = VoiceCard.fromJson(weather)!;
      expect(
        (c.type, c.title, c.value, c.icon),
        ('weather', 'Home', '21 °C', 'partlycloudy'),
      );
      expect(c.details, ['Humidity 60 %', 'Wind 12 km/h']);
      expect(c.forecast.map((f) => f.label), ['Mon', 'Tue']);
    });

    test(
      'is tolerant: unknown type becomes an entity card, junk is dropped',
      () {
        expect(
          VoiceCard.fromJson({'type': 'banana', 'title': 'X'})!.type,
          'entity',
        );
        expect(VoiceCard.fromJson('nope'), isNull);
        expect(VoiceCard.fromJson(const {}), isNull, reason: 'nothing to show');
        expect(
          VoiceCard.fromJson({
            'title': 'X',
            'forecast': 'bad',
            'details': null,
          })!.forecast,
          isEmpty,
        );
      },
    );

    test('the image goes through the URL rewriter', () {
      final c = VoiceCard.fromJson({
        'type': 'image',
        'title': 'Door',
        'image': '/api/camera_proxy/camera.door?token=t',
      }, url: (u) => 'http://ha$u');
      expect(c!.image, 'http://ha/api/camera_proxy/camera.door?token=t');
    });
  });

  group('controller', () {
    late FakePlatform platform;
    late VoiceController v;

    setUp(() {
      platform = FakePlatform();
      v = VoiceController(
        platform: platform,
        send: (m) => true,
        baseUrl: () => 'http://ha.local:8123',
        dismissAfter: const Duration(milliseconds: 50),
        silenceTimeout: const Duration(seconds: 5),
        followUpTimeout: () => const Duration(seconds: 5),
        soundsEnabled: () => false,
        dockedEnabled: () => platform.bubbleOk,
      );
    });
    tearDown(() => v.dispose());

    Map<String, dynamic> ev(
      String? session,
      String event, [
      Map<String, dynamic> data = const {},
    ]) => {
      'type': 'voice_event',
      'session': session,
      'event': event,
      'data': data,
    };

    test(
      'cards of an answer are attached to their turn, with picture paths rebased on the address we are connected through',
      () async {
        await v.listen();
        final first = v.session;
        v.onVoiceEvent(
          ev(first, 'cards', {
            'cards': [
              weather,
              {
                'type': 'image',
                'title': 'Door',
                'image': '/api/camera_proxy/camera.door?token=t',
              },
              {
                'type': 'media',
                'title': 'Song',
                'image': 'https://img.example/a.jpg',
              },
            ],
          }),
        );
        final cards = v.turns.last.cards;
        expect(cards.map((c) => c.type), ['weather', 'image', 'media']);
        expect(
          cards[1].image,
          'http://ha.local:8123/api/camera_proxy/camera.door?token=t',
        );
        expect(
          cards[2].image,
          'https://img.example/a.jpg',
          reason: 'a foreign URL is left alone',
        );
      },
    );

    test(
      'a card that arrives after the next listening has started still belongs to the earlier turn',
      () async {
        await v.listen();
        final first = v.session;
        v.onVoiceEvent(ev(first, 'stt-end', {'text': 'weather'}));
        v.onVoiceEvent(ev(first, 'tts-end', {'url': '/a.mp3'}));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(
          v.session,
          isNot(first),
          reason: 'the follow-up listening is a new session',
        );
        v.onVoiceEvent(
          ev(first, 'cards', {
            'cards': [weather],
          }),
        );
        expect(v.turns.first.cards, hasLength(1));
        expect(v.turns.last.cards, isEmpty);
      },
    );

    test('a card for a turn that is gone is ignored', () async {
      await v.listen();
      v.onVoiceEvent(
        ev('v-unknown', 'cards', {
          'cards': [weather],
        }),
      );
      expect(v.turns.last.cards, isEmpty);
    });

    test('the docked card is given the cards of the current turn', () async {
      platform.bubbleOk = true;
      await v.listen();
      v.onVoiceEvent(
        ev(v.session, 'cards', {
          'cards': [weather],
        }),
      );
      final snapshot = platform.bubbles.last['cards'] as List;
      expect(snapshot, hasLength(1));
      expect((snapshot.first as Map)['title'], 'Home');
      expect(((snapshot.first as Map)['forecast'] as List), hasLength(2));
    });

    test(
      'while waiting for a follow-up the docked card keeps the last answer and its cards',
      () async {
        platform.bubbleOk = true;
        await v.listen();
        final first = v.session;
        v.onVoiceEvent(ev(first, 'stt-end', {'text': 'weather'}));
        v.onVoiceEvent(ev(first, 'intent-end', {'text': 'Sunny.'}));
        v.onVoiceEvent(
          ev(first, 'cards', {
            'cards': [weather],
          }),
        );
        v.onVoiceEvent(ev(first, 'tts-end', {'url': '/a.mp3'}));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(v.state, VoiceState.listening);
        final snapshot = platform.bubbles.last;
        expect(snapshot['assistant'], 'Sunny.');
        expect((snapshot['cards'] as List), hasLength(1));
        // as soon as the new turn has words, the card shows it
        v.onVoiceEvent(ev(v.session, 'stt-end', {'text': 'and tomorrow'}));
        expect(platform.bubbles.last['user'], 'and tomorrow');
        expect((platform.bubbles.last['cards'] as List), isEmpty);
      },
    );

    test(
      'show_card without a conversation opens the screen with just the card and closes it again',
      () async {
        await v.showCards([weather], seconds: 1);
        expect(platform.calls, contains('show:/voice'));
        expect(v.turns.single.cards, hasLength(1));
        expect(v.state, VoiceState.idle);
        await Future<void>.delayed(const Duration(milliseconds: 1300));
        expect(platform.calls, contains('close:/voice'));
      },
    );

    test('show_card during a conversation joins the answer', () async {
      await v.listen();
      await v.showCards([weather]);
      expect(v.turns.last.cards, hasLength(1));
      expect(platform.calls.where((c) => c == 'close:/voice'), isEmpty);
    });

    test('a call with nothing showable does nothing', () async {
      await v.showCards([const {}, 'x']);
      expect(platform.calls, isEmpty);
    });
  });

  testWidgets(
    'the page shows weather, media, picture and entity cards under the answer',
    (tester) async {
      EasyLocalization.logger.enableLevels = [];
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = AppController(platform: FakePlatform());
      await c.refresh();
      await tester.pumpWidget(MaterialApp(home: VoicePage(controller: c)));
      c.voice
        ..state = VoiceState.speaking
        ..turns.add(
          VoiceTurn(
            user: 'what is the weather',
            assistant: 'Partly cloudy, 21 degrees.',
            cards: [
              VoiceCard.fromJson(weather)!,
              VoiceCard.fromJson({
                'type': 'media',
                'title': 'Song',
                'subtitle': 'Band — Album',
                'value': 'Playing',
              })!,
              VoiceCard.fromJson({'type': 'image', 'title': 'Front door'})!,
              VoiceCard.fromJson({
                'type': 'entity',
                'title': 'Kitchen light',
                'subtitle': 'Brightness 50 %',
                'value': 'On',
              })!,
            ],
          ),
        )
        ..notifyListeners();
      await tester.pump();
      expect(find.byKey(const ValueKey('card-weather')), findsOneWidget);
      expect(find.text('21 °C'), findsOneWidget);
      expect(find.text('Partly cloudy'), findsOneWidget);
      expect(find.text('Humidity 60 %  ·  Wind 12 km/h'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('22° / 12°'), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Band — Album'), findsOneWidget);
      expect(find.text('Front door'), findsOneWidget);
      expect(find.text('Kitchen light'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
    },
  );
}
