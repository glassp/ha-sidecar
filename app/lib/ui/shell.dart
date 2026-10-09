import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../settings/registry.dart';
import 'pages/alarms_page.dart';
import 'pages/home_page.dart';
import 'pages/section_page.dart';

/// Main navigation: a bottom bar on phones, a side rail on tablets.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.lock_outline, Icons.lock, 'Kiosk'),
    (Icons.brightness_6_outlined, Icons.brightness_6, 'Display'),
    (Icons.alarm_outlined, Icons.alarm, 'Alarms'),
    (Icons.tune, Icons.tune, 'System'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from an Android settings screen: permissions may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.refresh();
  }

  Widget _page() {
    final c = widget.controller;
    return switch (_index) {
      0 => HomePage(controller: c),
      1 => SectionPage(section: Section.kiosk, controller: c),
      2 => SectionPage(section: Section.display, controller: c),
      3 => AlarmsPage(controller: c),
      _ => SectionPage(section: Section.system, controller: c),
    };
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final i in _items) NavigationRailDestination(icon: Icon(i.$1), selectedIcon: Icon(i.$2), label: Text(i.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _page()),
        ]),
      );
    }
    return Scaffold(
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final i in _items) NavigationDestination(icon: Icon(i.$1), selectedIcon: Icon(i.$2), label: i.$3),
        ],
      ),
    );
  }
}
