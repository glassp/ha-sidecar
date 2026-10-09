import 'package:beamer/beamer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../settings/registry.dart';
import 'pages/alarms_page.dart';
import 'pages/home_page.dart';
import 'pages/section_page.dart';

/// Main navigation: a bottom bar on phones, a side rail on tablets.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, required this.delegate});
  final AppController controller;
  final BeamerDelegate delegate;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _paths = ['/', '/kiosk', '/display', '/alarms', '/system'];
  static const _items = [
    (Icons.home_outlined, Icons.home, 'nav.home'),
    (Icons.lock_outline, Icons.lock, 'nav.kiosk'),
    (Icons.brightness_6_outlined, Icons.brightness_6, 'nav.display'),
    (Icons.alarm_outlined, Icons.alarm, 'nav.alarms'),
    (Icons.tune, Icons.tune, 'nav.system'),
  ];

  /// The tab comes from the router location, so this page is never recreated when switching tabs.
  int get _index {
    final path =
        widget.delegate.currentBeamLocation.state.routeInformation.uri.path;
    final i = _paths.indexOf(path);
    return i < 0 ? 0 : i;
  }

  void _select(int i) => context.beamToNamed(_paths[i], stacked: false);

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.delegate,
    builder: (context, _) => _scaffold(context),
  );

  Widget _scaffold(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final i in _items)
                  NavigationRailDestination(
                    icon: Icon(i.$1),
                    selectedIcon: Icon(i.$2),
                    label: Text(i.$3.tr()),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _page()),
          ],
        ),
      );
    }
    return Scaffold(
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final i in _items)
            NavigationDestination(
              icon: Icon(i.$1),
              selectedIcon: Icon(i.$2),
              label: i.$3.tr(),
            ),
        ],
      ),
    );
  }
}
