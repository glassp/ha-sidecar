import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/routing.dart';

BeamerDelegate _delegate(String initial) => BeamerDelegate(
  initialPath: initial,
  locationBuilder: RoutesLocationBuilder(
    routes: {
      '/': (c, s, d) => const BeamPage(key: ValueKey('shell'), child: Text('home')),
      '/kiosk': (c, s, d) => const BeamPage(key: ValueKey('shell'), child: Text('kiosk')),
      '/search': (c, s, d) => const BeamPage(key: ValueKey('search'), child: Text('search')),
    },
  ).call,
);

Future<BeamerDelegate> _pump(WidgetTester t, String initial) async {
  final d = _delegate(initial);
  await t.pumpWidget(
    MaterialApp.router(
      routerDelegate: d,
      routeInformationParser: BeamerParser(),
      backButtonDispatcher: SidecarBackDispatcher(delegate: d),
    ),
  );
  await t.pumpAndSettle();
  return d;
}

String _loc(BeamerDelegate d) => d.currentBeamLocation.state.routeInformation.uri.path;

void main() {
  testWidgets('back pops the page, then the tab, then leaves only at the start page', (t) async {
    final d = await _pump(t, '/');
    d.beamToNamed('/kiosk', stacked: false);
    await t.pumpAndSettle();
    d.beamToNamed('/search', stacked: false);
    await t.pumpAndSettle();

    expect(await t.binding.handlePopRoute(), isTrue);
    await t.pumpAndSettle();
    expect(_loc(d), '/kiosk');
    expect(await t.binding.handlePopRoute(), isTrue);
    await t.pumpAndSettle();
    expect(_loc(d), '/');
    expect(await t.binding.handlePopRoute(), isFalse);
  });

  testWidgets('with no history, back from a page goes to the start page instead of closing', (t) async {
    final d = await _pump(t, '/search');
    expect(await t.binding.handlePopRoute(), isTrue);
    await t.pumpAndSettle();
    expect(_loc(d), '/');
    expect(find.text('home'), findsOneWidget);
    expect(await t.binding.handlePopRoute(), isFalse);
  });
}
