import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../settings/registry.dart';
import '../design.dart';
import 'section_page.dart';

void openSearch(BuildContext context, AppController c) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(controller: c)));
}

/// Search across every setting. Results are the real controls, editable right here.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller, this.initialQuery = ''});
  final AppController controller;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);

  static const _suggestions = ['night light', 'dashboard', 'dim', 'PIN', 'camera', 'permission', 'brightness', 'idle screen', 'theme', 'update'];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: widget.initialQuery.isEmpty,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search settings',
            border: InputBorder.none,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_query.clear)),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final all = buildRegistry(widget.controller);
          final results = searchSettings(all, _query.text);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                children: [
                  if (_query.text.trim().isEmpty) ...[
                    const SectionTitle('Try searching for'),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in _suggestions)
                        ActionChip(label: Text(s), onPressed: () => setState(() => _query.text = s)),
                    ]),
                    const SectionTitle('Browse'),
                    GroupCard(children: [
                      for (final s in Section.values)
                        Tile(
                          icon: s.icon,
                          title: s.label,
                          subtitle: s.subtitle,
                          onTap: () => setState(() => _query.text = s.label),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                    ]),
                  ] else if (results.isEmpty) ...[
                    const SizedBox(height: 48),
                    Icon(Icons.search_off, size: 48, color: t.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text('No setting matches "${_query.text}"', textAlign: TextAlign.center, style: t.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Try a shorter word, like "dim", "night" or "url".', textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
                  ] else ...[
                    HelpText('${results.length} result${results.length == 1 ? '' : 's'}'),
                    for (final e in results) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                        child: InkWell(
                          onTap: () => openEntry(context, widget.controller, e.id),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(children: [
                            Icon(e.section.icon, size: 14, color: t.colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(e.breadcrumb, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary)),
                            const Spacer(),
                            Text('Open', style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                            Icon(Icons.chevron_right, size: 16, color: t.colorScheme.onSurfaceVariant),
                          ]),
                        ),
                      ),
                      GroupCard(children: [Builder(builder: e.builder)]),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
