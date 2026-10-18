import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/app_controller.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/settings/registry.dart';
import 'package:ha_sidecar/ui/design.dart';

/// Reports the microphone effects the way the Kotlin side does and records what the settings ask for.
class FakePlatform extends Fake implements KioskPlatform {
  FakePlatform({this.cfg = const {}, this.state = const {}});
  Map<String, dynamic> cfg;
  Map<String, dynamic> state;
  final configs = <Map<String, dynamic>>[];

  @override
  Future<DeviceStatus> getStatus() async =>
      DeviceStatus({...state, 'cfg': cfg});

  @override
  Future<List<AlarmSpec>> getAlarms() async => const [];

  @override
  Future<Map<String, dynamic>> setDisplayConfig(Map<String, dynamic> c) async {
    configs.add(c);
    cfg = {...cfg, ...c};
    return cfg;
  }
}

Future<(AppController, FakePlatform)> show(
  WidgetTester tester,
  String id, {
  Map<String, dynamic> cfg = const {},
  Map<String, dynamic> state = const {},
}) async {
  final platform = FakePlatform(cfg: cfg, state: state);
  final controller = AppController(platform: platform);
  await controller.refresh();
  final entry = buildRegistry(controller).firstWhere((e) => e.id == id);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Builder(builder: entry.builder)),
    ),
  );
  return (controller, platform);
}

void main() {
  EasyLocalization.logger.enableLevels =
      []; // the strings are not loaded in these tests; keys are fine

  testWidgets(
    'the voice group lists echo cancellation, its status, noise suppression and the source',
    (tester) async {
      final c = AppController(platform: FakePlatform());
      final ids = [
        for (final e in buildRegistry(
          c,
        ).where((e) => e.section == Section.system))
          e.id,
      ];
      for (final id in const [
        'echo_cancellation',
        'echo_status',
        'noise_suppression',
        'mic_source',
      ]) {
        expect(ids, contains(id));
      }
    },
  );

  testWidgets(
    'echo cancellation offers auto / on / off, shows the stored mode and writes the choice',
    (tester) async {
      final (_, platform) = await show(
        tester,
        'echo_cancellation',
        cfg: {'echo_cancellation': 'on'},
      );
      for (final label in const [
        'mic.echo_auto',
        'mic.echo_on',
        'mic.echo_off',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final selected = tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected;
      expect(selected, {'on'});

      await tester.tap(find.text('mic.echo_off'));
      await tester.pumpAndSettle();
      expect(platform.configs, [
        {'echo_cancellation': 'off'},
      ]);
    },
  );

  testWidgets('a config without the setting shows auto', (tester) async {
    await show(tester, 'echo_cancellation');
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'auto'},
    );
  });

  testWidgets(
    'the source setting offers the three sources and writes the choice',
    (tester) async {
      final (_, platform) = await show(tester, 'mic_source');
      for (final label in const [
        'mic.source_auto',
        'mic.source_voice_recognition',
        'mic.source_voice_communication',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('mic.source_voice_communication'));
      await tester.pumpAndSettle();
      expect(platform.configs, [
        {'mic_source': 'voice_communication'},
      ]);
    },
  );

  testWidgets(
    'noise suppression is a switch that is off until it is switched on',
    (tester) async {
      final (_, platform) = await show(tester, 'noise_suppression');
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(platform.configs, [
        {'noise_suppression': true},
      ]);
    },
  );

  testWidgets('an active canceller is reported with the source that records', (
    tester,
  ) async {
    await show(
      tester,
      'echo_status',
      state: {
        'echo_cancellation_state': 'active',
        'mic_source_in_use': 'voice_recognition',
      },
    );
    expect(find.text('mic.state_active'), findsOneWidget);
    expect(find.textContaining('mic.echo_state_active'), findsOneWidget);
    // the source is named (the key is rendered as is without loaded strings)
    expect(find.textContaining('mic.source_in_use'), findsOneWidget);
    expect(find.textContaining('mic.noise_state'), findsNothing);
  });

  testWidgets(
    'noise suppression is only mentioned in the status once it is wanted',
    (tester) async {
      await show(
        tester,
        'echo_status',
        cfg: {'noise_suppression': true},
        state: {
          'echo_cancellation_state': 'idle',
          'noise_suppression_state': 'unavailable',
        },
      );
      expect(find.text('mic.state_idle'), findsOneWidget);
      expect(
        find.textContaining('mic.noise_state_unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('mic.source_in_use'), findsNothing);
    },
  );

  testWidgets(
    'a tablet without a canceller is a warning only when the mode says on',
    (tester) async {
      Color? pillColor() => tester.widget<Pill>(find.byType(Pill)).color;

      await show(
        tester,
        'echo_status',
        cfg: {'echo_cancellation': 'auto'},
        state: {'echo_cancellation_state': 'unavailable'},
      );
      expect(find.text('mic.state_unavailable'), findsOneWidget);
      expect(pillColor(), isNull);

      await show(
        tester,
        'echo_status',
        cfg: {'echo_cancellation': 'on'},
        state: {'echo_cancellation_state': 'unavailable'},
      );
      expect(pillColor(), Semantic.warn);
    },
  );
}
