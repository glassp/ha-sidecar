import 'package:beamer/beamer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'routing.dart';

/// Owned by the Dart isolate, not the widget tree: the isolate also runs headless (started by
/// the Android KeepAliveService at boot), where no widget is ever built.
final controller = AppController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await controller.init();
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('de')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      useOnlyLangCode: true,
      child: const SidecarApp(),
    ),
  );
}

class SidecarApp extends StatefulWidget {
  const SidecarApp({super.key});

  @override
  State<SidecarApp> createState() => _SidecarAppState();
}

class _SidecarAppState extends State<SidecarApp> {
  late final AppRouter router = AppRouter(
    controller,
    initialPath: controller.setupDone && controller.settings.isPaired
        ? '/'
        : '/wizard',
  );

  // theme is a setting (also a HA select entity): system | light | dark | night (dark while it is night)
  ThemeMode get _themeMode {
    final s = controller.status;
    return switch (s.cfg['theme']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'night' => s.isNight ? ThemeMode.dark : ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  static const _seed = Color(0xFF03A9F4);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => MaterialApp.router(
        onGenerateTitle: (_) => 'app.name'.tr(),
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: _seed,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        routerDelegate: router.delegate,
        routeInformationParser: BeamerParser(),
        backButtonDispatcher: BeamerBackButtonDispatcher(
          delegate: router.delegate,
        ),
      ),
    );
  }
}
