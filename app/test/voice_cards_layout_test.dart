import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/ui/voice_cards.dart';
import 'package:ha_sidecar/voice/voice_card.dart';

VoiceCard weather(int days) => VoiceCard.fromJson({
  'type': 'weather',
  'title': 'Demo Weather North',
  'subtitle': 'Rainy',
  'value': '15 °C',
  'icon': 'rainy',
  'details': ['Humidity 54 %', 'Wind 7.7 km/h', 'Pressure 1023.7 hPa'],
  'forecast': [
    for (var i = 0; i < days; i++)
      {'label': 'Day $i', 'value': '22° / 12°', 'icon': 'sunny'},
  ],
  'entity_id': 'weather.demo',
})!;

Future<void> pumpAt(WidgetTester tester, double width, VoiceCard card) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ResultCards([card]),
        ),
      ),
    ),
  );
}

void main() {
  for (final width in [360.0, 411.0, 600.0, 1024.0]) {
    testWidgets('weather card with a four day forecast fits at $width wide', (
      tester,
    ) async {
      await pumpAt(tester, width, weather(4));
      expect(tester.takeException(), isNull);
      // the details line keeps a readable width instead of one letter per line
      final details = tester.getSize(
        find.textContaining('Humidity 54 %').first,
      );
      expect(details.width, greaterThan(150));
      expect(details.height, lessThan(80));
    });
  }

  testWidgets('weather card without a forecast still fits a phone', (
    tester,
  ) async {
    await pumpAt(tester, 360, weather(0));
    expect(tester.takeException(), isNull);
    expect(find.text('Rainy'), findsOneWidget);
  });
}
