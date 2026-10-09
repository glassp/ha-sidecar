import 'package:beamer/beamer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../settings/registry.dart';
import '../design.dart';
import 'section_page.dart';

/// Search across every setting. Results are the real controls, editable right here.
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.controller,
    this.initialQuery = '',
  });
  final AppController controller;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final suggestions = 'search.suggestions'
        .tr()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.beamBack()),
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: widget.initialQuery.isEmpty,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'search.title'.tr(),
            border: InputBorder.none,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_query.clear),
                  ),
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
                    SectionTitle('search.try'.tr()),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in suggestions)
                          ActionChip(
                            label: Text(s),
                            onPressed: () => setState(() => _query.text = s),
                          ),
                      ],
                    ),
                    SectionTitle('search.browse'.tr()),
                    GroupCard(
                      children: [
                        for (final s in Section.values)
                          Tile(
                            icon: s.icon,
                            title: s.label,
                            subtitle: s.subtitle,
                            onTap: () => setState(() => _query.text = s.label),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                      ],
                    ),
                  ] else if (results.isEmpty) ...[
                    const SizedBox(height: 48),
                    Icon(
                      Icons.search_off,
                      size: 48,
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'search.none'.tr(namedArgs: {'query': _query.text}),
                      textAlign: TextAlign.center,
                      style: t.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'search.none_hint'.tr(),
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium,
                    ),
                  ] else ...[
                    HelpText('search.results'.plural(results.length)),
                    for (final e in results) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                        child: InkWell(
                          onTap: () =>
                              openEntry(context, widget.controller, e.id),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: [
                              Icon(
                                e.section.icon,
                                size: 14,
                                color: t.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                e.breadcrumb,
                                style: t.textTheme.labelMedium?.copyWith(
                                  color: t.colorScheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'search.open'.tr(),
                                style: t.textTheme.labelMedium?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: t.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
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
