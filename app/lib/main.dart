import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/shell.dart';
import 'ui/wizard/wizard.dart';

/// Owned by the Dart isolate, not the widget tree: the isolate also runs headless (started by
/// the Android KeepAliveService at boot), where no widget is ever built.
final controller = AppController();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  controller.init();
  runApp(const SidecarApp());
}

class SidecarApp extends StatelessWidget {
  const SidecarApp({super.key});

  @override
  Widget build(BuildContext context) {
    // theme is a setting (also a HA select entity): system | light | dark | night (dark while it is night)
    return ListenableBuilder(listenable: controller, builder: (context, _) => _app(context));
  }

  ThemeMode get _themeMode {
    final s = controller.status;
    return switch (s.cfg['theme']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'night' => s.isNight ? ThemeMode.dark : ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  Widget _app(BuildContext context) {
    return MaterialApp(
      title: 'HA Sidecar',
      themeMode: _themeMode,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF03A9F4), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF03A9F4),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          return controller.setupDone && controller.settings.isPaired ? AppShell(controller: controller) : WizardScreen(controller: controller);
        },
      ),
    );
  }
}
