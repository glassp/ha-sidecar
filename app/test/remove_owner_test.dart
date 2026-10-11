import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/app_controller.dart';
import 'package:ha_sidecar/platform/kiosk_platform.dart';
import 'package:ha_sidecar/ui/dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlatform extends Fake implements KioskPlatform {
  bool hasPin = true;
  int pinResult = 0; // 0 ok, -1 wrong, >0 locked out (ms)
  final calls = <String>[];

  @override
  Future<DeviceStatus> getStatus() async =>
      DeviceStatus({'has_pin': hasPin, 'device_owner': true});
  @override
  Future<List<AlarmSpec>> getAlarms() async => const [];
  @override
  Future<int> unlockWithPin(String pin) async {
    calls.add('pin:$pin');
    return pinResult;
  }

  @override
  Future<void> clearDeviceOwner() async => calls.add('clear');
}

Future<(FakePlatform, AppController)> open(WidgetTester tester) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableLevels = [];
  final platform = FakePlatform();
  final c = AppController(platform: platform);
  await c.refresh();
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRemoveOwnerDialog(context, c),
                child: const Text('open'),
              ),
            ),
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
  return (platform, c);
}

void main() {
  testWidgets(
    'device owner is only removed after the right PIN; a wrong PIN changes nothing',
    (tester) async {
      final (platform, c) = await open(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Give up device owner?'), findsOneWidget);

      platform.pinResult = -1;
      await tester.enterText(find.byType(TextField), '0000');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(platform.calls, ['pin:0000'], reason: 'nothing was removed');

      platform.pinResult = 0;
      await tester.enterText(find.byType(TextField), '2468');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(platform.calls, ['pin:0000', 'pin:2468', 'clear']);
      expect(find.text('Device owner removed'), findsOneWidget);

      // without a PIN there is no field, and Cancel removes nothing
      platform
        ..hasPin = false
        ..calls.clear();
      await c.refresh();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(platform.calls, isEmpty);
    },
  );
}
