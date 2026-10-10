import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/app_controller.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/ui/wake_words_dialog.dart';

/// Keeps the wake word state a tablet would report and records what the dialog asks for.
class FakePlatform extends Fake implements KioskPlatform {
  FakePlatform(this.words);
  List<Map<String, dynamic>> words;
  String? downloading;
  final calls = <String>[];
  final configs = <Map<String, dynamic>>[];

  @override
  Future<DeviceStatus> getStatus() async => DeviceStatus({
    'wake_words': words,
    'wake_word_downloading': downloading,
    'wake_word_download_fraction': 0.4,
    'cfg': <String, dynamic>{},
  });

  @override
  Future<List<AlarmSpec>> getAlarms() async => const [];

  @override
  Future<Map<String, dynamic>> setDisplayConfig(Map<String, dynamic> c) async {
    configs.add(c);
    final ids = (c['wake_word_ids'] as String)
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
    words = [
      for (final w in words) {...w, 'active': ids.contains(w['id'])},
    ];
    return {};
  }

  @override
  Future<void> downloadWakeWord(String id) async => calls.add('download:$id');

  @override
  Future<void> removeWakeWord(String id) async => calls.add('remove:$id');
}

Map<String, dynamic> word(
  String id,
  String phrase, {
  bool installed = false,
  bool active = false,
  bool downloading = false,
  bool queued = false,
}) => {
  'id': id,
  'phrase': phrase,
  'installed': installed,
  'active': active,
  'downloading': downloading,
  'queued': queued,
  'size_bytes': 207512,
  'missing_bytes': installed ? 0 : 2800000,
  'source': 'test',
};

Future<(AppController, FakePlatform)> open(
  WidgetTester tester,
  List<Map<String, dynamic>> words,
) async {
  final platform = FakePlatform(words);
  final controller = AppController(platform: platform);
  await controller.refresh();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showWakeWordsDialog(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (controller, platform);
}

void main() {
  EasyLocalization.logger.enableLevels =
      []; // the strings are not loaded in these tests; keys are fine
  testWidgets('lists every phrase with a download button or a remove button', (
    tester,
  ) async {
    await open(tester, [
      word('hey_jarvis', 'Hey Jarvis', installed: true, active: true),
      word('alexa', 'Alexa'),
      word('computer', 'Computer', installed: true),
    ]);
    expect(find.text('Hey Jarvis'), findsOneWidget);
    expect(find.text('Alexa'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wake-remove-hey_jarvis')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('wake-remove-computer')), findsOneWidget);
    expect(find.byKey(const ValueKey('wake-download-alexa')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wake-download-hey_jarvis')),
      findsNothing,
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('wake-check-hey_jarvis')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('wake-check-alexa')))
          .value,
      isFalse,
    );
  });

  testWidgets(
    'ticking several phrases chooses all of them, unticking removes one',
    (tester) async {
      final (_, platform) = await open(tester, [
        word('hey_jarvis', 'Hey Jarvis', installed: true, active: true),
        word('alexa', 'Alexa'),
        word('computer', 'Computer', installed: true),
      ]);
      await tester.tap(find.byKey(const ValueKey('wake-check-alexa')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wake-check-computer')));
      await tester.pumpAndSettle();
      expect(platform.configs.map((c) => c['wake_word_ids']), [
        'hey_jarvis,alexa',
        'hey_jarvis,alexa,computer',
      ]);
      await tester.tap(find.byKey(const ValueKey('wake-check-hey_jarvis')));
      await tester.pumpAndSettle();
      expect(platform.configs.last['wake_word_ids'], 'alexa,computer');
    },
  );

  testWidgets('quick successive ticks do not undo each other', (tester) async {
    final (_, platform) = await open(tester, [
      word('hey_jarvis', 'Hey Jarvis', installed: true, active: true),
      word('alexa', 'Alexa'),
      word('jarvis', 'Jarvis'),
      word('computer', 'Computer'),
    ]);
    // no frame in between: the tablet's status has not caught up with the first tap when the next one lands
    await tester.tap(find.byKey(const ValueKey('wake-check-alexa')));
    await tester.tap(find.byKey(const ValueKey('wake-check-jarvis')));
    await tester.tap(find.byKey(const ValueKey('wake-check-computer')));
    await tester.pumpAndSettle();
    expect(
      platform.configs.last['wake_word_ids'],
      'hey_jarvis,alexa,jarvis,computer',
    );
    expect(platform.words.where((w) => w['active'] == true).length, 4);
  });

  testWidgets('download and remove go to the platform', (tester) async {
    final (_, platform) = await open(tester, [
      word('hey_jarvis', 'Hey Jarvis', installed: true, active: true),
      word('alexa', 'Alexa'),
    ]);
    await tester.tap(find.byKey(const ValueKey('wake-download-alexa')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wake-remove-hey_jarvis')));
    await tester.pumpAndSettle();
    expect(platform.calls, ['download:alexa', 'remove:hey_jarvis']);
  });

  testWidgets(
    'a model that downloads shows progress and no buttons; a queued one waits',
    (tester) async {
      final platform = FakePlatform([
        word('alexa', 'Alexa', downloading: true),
        word('computer', 'Computer', queued: true),
        word('jarvis', 'Jarvis'),
      ])..downloading = 'alexa';
      final controller = AppController(platform: platform);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WakeWordsDialog(controller: controller)),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('wake-download-alexa')), findsNothing);
      expect(
        find.byKey(const ValueKey('wake-download-computer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('wake-download-jarvis')),
        findsOneWidget,
      );
    },
  );
}
