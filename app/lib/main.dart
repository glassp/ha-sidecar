import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/home_screen.dart';
import 'ui/setup_screen.dart';

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
    return MaterialApp(
      title: 'HA Sidecar',
      themeMode: ThemeMode.system,
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
          return controller.settings.isPaired ? HomeScreen(controller: controller) : SetupScreen(controller: controller);
        },
      ),
    );
  }
}
