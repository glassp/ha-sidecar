import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/app_controller.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/ui/pages/voice_page.dart';
import 'package:ha_sidecar/voice/voice_controller.dart';

class FakePlatform extends Fake implements KioskPlatform {
  @override
  Future<DeviceStatus> getStatus() async => DeviceStatus({'timers': timers});
  @override
  Future<List<AlarmSpec>> getAlarms() async => const [];
  @override
  Future<void> closeUi(String route) async {}
  @override
  Future<void> voiceStopPlayback() async {}
  @override
  Future<void> voiceStop() async {}
  @override
  Future<void> voicePing(String kind) async {}
  @override
  Future<bool> showUi(String route) async => true;
  @override
  Future<String?> voiceStart(String session) async => null;
  List<Map<String, dynamic>> timers = [];
}

Map<String, dynamic> timer(
  String id,
  String label, {
  String state = 'running',
  int duration = 180000,
  int remaining = 120000,
}) => {
  'id': id,
  'label': label,
  'kind': 'countdown',
  'state': state,
  'duration_ms': duration,
  'elapsed_ms': duration - remaining,
  'remaining_ms': remaining,
  'ends_at': DateTime.now().millisecondsSinceEpoch + remaining,
  'started_at': DateTime.now().millisecondsSinceEpoch - (duration - remaining),
};

Future<(AppController, FakePlatform)> show(
  WidgetTester tester, {
  List<Map<String, dynamic>> timers = const [],
}) async {
  EasyLocalization.logger.enableLevels = [];
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final platform = FakePlatform()..timers = [...timers];
  final c = AppController(platform: platform);
  await c.refresh();
  await tester.pumpWidget(MaterialApp(home: VoicePage(controller: c)));
  await tester.pump();
  return (c, platform);
}

void main() {
  testWidgets(
    'shows what you said and what the assistant answered as bubbles',
    (tester) async {
      final (c, _) = await show(tester);
      c.voice
        ..state = VoiceState.speaking
        ..turns.add(
          VoiceTurn(user: 'what time is it', assistant: 'It is noon.'),
        )
        ..notifyListeners();
      await tester.pump();
      expect(find.text('what time is it'), findsOneWidget);
      expect(find.text('It is noon.'), findsOneWidget);
      expect(find.byKey(const ValueKey('bubble-user')), findsOneWidget);
      expect(find.byKey(const ValueKey('bubble-assistant')), findsOneWidget);
    },
  );

  testWidgets(
    'while listening an empty bubble waits for the words and the buttons offer to finish or cancel',
    (tester) async {
      final (c, _) = await show(tester);
      c.voice
        ..state = VoiceState.listening
        ..turns.add(VoiceTurn())
        ..notifyListeners();
      await tester.pump();
      expect(find.byKey(const ValueKey('bubble-user')), findsOneWidget);
      expect(find.byKey(const ValueKey('bubble-assistant')), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    },
  );

  testWidgets(
    'earlier turns of a conversation stay on screen, only the last three',
    (tester) async {
      final (c, _) = await show(tester);
      c.voice
        ..state = VoiceState.speaking
        ..turns.addAll([
          for (var i = 1; i <= 5; i++) VoiceTurn(user: 'q$i', assistant: 'a$i'),
        ])
        ..notifyListeners();
      await tester.pump();
      expect(find.text('q1'), findsNothing);
      expect(find.text('q2'), findsNothing);
      for (final t in ['q3', 'a3', 'q4', 'a4', 'q5', 'a5']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    },
  );

  testWidgets(
    'running timers show as pills with the time left and their label; a paused one looks paused',
    (tester) async {
      await show(
        tester,
        timers: [
          timer('a', 'pasta', remaining: 178000),
          timer('b', '', state: 'paused', remaining: 60000),
        ],
      );
      expect(find.byKey(const ValueKey('timer-pill-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('timer-pill-b')), findsOneWidget);
      expect(find.text('pasta'), findsOneWidget);
      expect(
        find.textContaining('2:5'),
        findsOneWidget,
        reason: 'about 2:58 left',
      );
      expect(find.byIcon(Icons.pause), findsOneWidget);
    },
  );

  testWidgets('a timer that ran out shows the time it is over', (tester) async {
    await show(
      tester,
      timers: [
        {
          ...timer('c', 'tea', state: 'finished', remaining: 0),
          'finished_at': DateTime.now().millisecondsSinceEpoch - 5000,
        },
      ],
    );
    expect(find.textContaining('+0:0'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
  });

  testWidgets('an error is a red bubble with a way to try again', (
    tester,
  ) async {
    final (c, _) = await show(tester);
    c.voice
      ..state = VoiceState.error
      ..errorCode = 'stt-stream-failed'
      ..errorMessage = 'speech-to-text failed'
      ..turns.add(VoiceTurn())
      ..notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('bubble-error')), findsOneWidget);
    expect(find.text('speech-to-text failed'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-again')), findsOneWidget);
  });

  testWidgets(
    'a follow-up listening says so, shows the draining wait bar and offers to end the conversation',
    (tester) async {
      final (c, _) = await show(tester);
      c.voice
        ..state = VoiceState.listening
        ..inConversation = true
        ..followUp = true
        ..waitingForSpeech = true
        ..speechWindow = const Duration(seconds: 8)
        ..session = 's1'
        ..turns.add(VoiceTurn(assistant: 'It is noon.'))
        ..turns.add(VoiceTurn())
        ..notifyListeners();
      await tester.pump();
      expect(find.text('voice.listening_followup'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-end')), findsOneWidget);
      expect(find.text('voice.end_conversation'), findsOneWidget);
      expect(
        find.text('It is noon.'),
        findsOneWidget,
        reason: 'the answer stays while we wait',
      );
      await tester.pumpWidget(
        const SizedBox(),
      ); // stop the animations before the test ends
    },
  );
}
