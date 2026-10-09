import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../settings/registry.dart';
import '../design.dart';
import 'search_page.dart';

/// Groups of a section, in registry order.
Map<String, List<SettingEntry>> groupsOf(List<SettingEntry> all, Section section) {
  final map = <String, List<SettingEntry>>{};
  for (final e in all.where((e) => e.section == section)) {
    map.putIfAbsent(e.group, () => []).add(e);
  }
  return map;
}

Widget searchAction(BuildContext context, AppController c) => IconButton(
      icon: const Icon(Icons.search),
      tooltip: 'Search settings',
      onPressed: () => openSearch(context, c),
    );

/// One tab of the app: all groups of a section as cards.
class SectionPage extends StatelessWidget {
  const SectionPage({super.key, required this.section, required this.controller});
  final Section section;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final groups = groupsOf(buildRegistry(controller), section);
        return AppPage(
          title: section.label,
          actions: [searchAction(context, controller)],
          children: [
            HelpText(section.subtitle),
            for (final g in groups.entries) ...[
              SectionTitle(g.key),
              GroupCard(children: [for (final e in g.value) Builder(builder: e.builder)]),
            ],
          ],
        );
      },
    );
  }
}

/// A single group opened from a "needs attention" fix or a search result.
class GroupPage extends StatelessWidget {
  const GroupPage({super.key, required this.controller, required this.entryId});
  final AppController controller;
  final String entryId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final all = buildRegistry(controller);
        final entry = all.firstWhere((e) => e.id == entryId, orElse: () => all.first);
        final inGroup = all.where((e) => e.section == entry.section && e.group == entry.group).toList();
        return AppPage(
          title: entry.group,
          actions: [searchAction(context, controller)],
          children: [
            HelpText('${entry.section.label} › ${entry.group}'),
            const SizedBox(height: 8),
            GroupCard(children: [for (final e in inGroup) Builder(builder: e.builder)]),
          ],
        );
      },
    );
  }
}

void openEntry(BuildContext context, AppController c, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupPage(controller: c, entryId: id)));
}
