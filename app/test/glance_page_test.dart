import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/app_controller.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/ui/pages/glance_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlatform extends Fake implements KioskPlatform {
  @override
  Future<DeviceStatus> getStatus() async => DeviceStatus({});
  @override
  Future<List<AlarmSpec>> getAlarms() async => const [];
}

void main() {
  // The clock is 150 sp text: on a 360 dp phone it used to wrap into "23:0" and "2".
  testWidgets('the clock stays on one line on a phone and on a tablet', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    final c = AppController(platform: FakePlatform());
    await c.refresh();

    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: MediaQuery(
              data: const MediaQueryData(alwaysUse24HourFormat: true),
              child: GlancePage(controller: c),
            ),
          ),
        ),
      ),
    );
    // the translations load from the asset bundle, which needs real time
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    for (final width in [360.0, 411.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final clock = find.textContaining(RegExp(r'^\d\d:\d\d$'));
      expect(clock, findsOneWidget, reason: 'at $width');
      // one line of the 150 sp text, not two
      expect(tester.getSize(clock).height, lessThan(160), reason: 'at $width');
      // the box that scales it fits the screen (the text inside keeps its natural size)
      final box = find.ancestor(of: clock, matching: find.byType(FittedBox));
      expect(
        tester.getSize(box.first).width,
        lessThanOrEqualTo(width),
        reason: 'at $width',
      );
    }
  });
}
