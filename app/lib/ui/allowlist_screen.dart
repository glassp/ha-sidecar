import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../platform/kiosk_platform.dart';

/// Pick which apps may run while locked down (besides the HA app and the keyboard).
class AllowlistScreen extends StatefulWidget {
  const AllowlistScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<AllowlistScreen> createState() => _AllowlistScreenState();
}

class _AllowlistScreenState extends State<AllowlistScreen> {
  late final Future<List<LaunchableApp>> _apps = widget.controller.platform.listLaunchableApps();
  late final Set<String> _selected = {...widget.controller.status.allowlist};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Allowed apps'),
        actions: [
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              await widget.controller.platform.setAllowlist(_selected.toList());
              await widget.controller.refresh();
              nav.pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: FutureBuilder<List<LaunchableApp>>(
        future: _apps,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            children: [
              for (final app in snap.data!)
                CheckboxListTile(
                  title: Text(app.label),
                  subtitle: Text(app.package),
                  value: _selected.contains(app.package),
                  onChanged: (v) => setState(() => v == true ? _selected.add(app.package) : _selected.remove(app.package)),
                ),
            ],
          );
        },
      ),
    );
  }
}
