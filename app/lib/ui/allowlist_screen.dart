import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../platform/kiosk_platform.dart';
import 'design.dart';

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
  String _query = '';

  Future<void> _save() async {
    final nav = Navigator.of(context);
    await widget.controller.platform.setAllowlist(_selected.toList());
    await widget.controller.refresh();
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Allowed apps'),
        actions: [Padding(padding: const EdgeInsets.only(right: 8), child: FilledButton(onPressed: _save, child: const Text('Save')))],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentWidth),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('While the kiosk is locked only these apps can be opened. The Home Assistant app and the keyboard are always allowed.'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search apps',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<LaunchableApp>>(
                  future: _apps,
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final apps = snap.data!.where((a) => a.label.toLowerCase().contains(_query) || a.package.contains(_query)).toList();
                    return ListView(
                      children: [
                        for (final app in apps)
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
