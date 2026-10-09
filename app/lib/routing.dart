import 'package:beamer/beamer.dart';
import 'package:flutter/widgets.dart';

import 'app_controller.dart';
import 'ui/allowlist_screen.dart';
import 'ui/pages/alarm_page.dart';
import 'ui/pages/glance_page.dart';
import 'ui/pages/pin_page.dart';
import 'ui/pages/search_page.dart';
import 'ui/pages/section_page.dart';
import 'ui/pages/voice_page.dart';
import 'ui/shell.dart';
import 'ui/wizard/wizard.dart';

/// All navigation goes through beamer. Paths:
///   /  /kiosk  /display  /alarms  /system   main tabs (one shell page)
///   /search  /settings/:id  /allowed-apps    pushed pages
///   /wizard                                  first-run guide
///   /pin  /alarm  /glance  /voice            full-screen pages hosted by their own Android activity
///                                             (the native side tells us which one is on screen)
class AppRouter {
  AppRouter(this.controller, {required String initialPath}) {
    delegate = BeamerDelegate(
      initialPath: initialPath,
      setBrowserTabTitle: false,
      locationBuilder: RoutesLocationBuilder(
        routes: {
          '/': (context, state, data) => _shell(0),
          '/kiosk': (context, state, data) => _shell(1),
          '/display': (context, state, data) => _shell(2),
          '/alarms': (context, state, data) => _shell(3),
          '/system': (context, state, data) => _shell(4),
          '/search': (context, state, data) => BeamPage(
            key: const ValueKey('search'),
            child: SearchPage(
              controller: controller,
              initialQuery: state.queryParameters['q'] ?? '',
            ),
          ),
          '/settings/:id': (context, state, data) => BeamPage(
            key: ValueKey('settings-${state.pathParameters['id']}'),
            child: GroupPage(
              controller: controller,
              entryId: state.pathParameters['id']!,
            ),
          ),
          '/allowed-apps': (context, state, data) => BeamPage(
            key: const ValueKey('allowed'),
            child: AllowlistScreen(controller: controller),
          ),
          '/wizard': (context, state, data) => BeamPage(
            key: const ValueKey('wizard'),
            child: WizardScreen(controller: controller),
          ),
          '/pin': (context, state, data) => BeamPage(
            key: const ValueKey('pin'),
            child: PinPage(controller: controller),
          ),
          '/alarm': (context, state, data) => BeamPage(
            key: const ValueKey('alarm'),
            child: AlarmPage(controller: controller),
          ),
          '/voice': (context, state, data) => BeamPage(
            key: const ValueKey('voice'),
            child: VoicePage(controller: controller),
          ),
          '/glance': (context, state, data) => BeamPage(
            key: const ValueKey('glance'),
            child: GlancePage(controller: controller),
          ),
        },
      ).call,
    );
    delegate.addListener(_remember);
    controller.onNavigate = (path) =>
        delegate.beamToNamed(path, stacked: false);
    controller.onUiRoute = _onNativeRoute;
  }

  final AppController controller;
  late final BeamerDelegate delegate;

  static const nativeHosted = {'/pin', '/alarm', '/glance', '/voice'};
  String _lastMain = '/';

  BeamPage _shell(int tab) => BeamPage(
    key: const ValueKey('shell'),
    child: AppShell(controller: controller, delegate: delegate),
  );

  void _remember() {
    final uri = delegate.currentBeamLocation.state.routeInformation.uri;
    if (!nativeHosted.contains(uri.path)) _lastMain = uri.toString();
  }

  /// Native side reports which activity is in front: `main` or one of [nativeHosted].
  void _onNativeRoute(String route) {
    final target = route == 'main' ? _lastMain : route;
    if (delegate.currentBeamLocation.state.routeInformation.uri.toString() !=
        target) {
      delegate.beamToNamed(target, stacked: false);
    }
  }
}
