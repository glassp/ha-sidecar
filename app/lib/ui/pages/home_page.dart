import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../ha/sidecar_client.dart';
import '../../health.dart';
import '../../platform/kiosk_platform.dart';
import '../design.dart';
import '../dialogs.dart';
import 'search_page.dart';
import 'section_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ValueListenableBuilder<LinkState>(
        valueListenable: controller.link ?? ValueNotifier(LinkState.disconnected),
        builder: (context, link, _) {
          final s = controller.status;
          final issues = computeIssues(controller, link, (ctx, id) => openEntry(ctx, controller, id));
          final problems = issues.where((i) => i.severity == Severity.problem).toList();
          final suggestions = issues.where((i) => i.severity == Severity.suggestion).toList();
          return AppPage(
            title: 'HA Sidecar',
            actions: [searchAction(context, controller)],
            children: [
              _Hero(controller: controller, link: link, blocked: problems.isNotEmpty),
              if (problems.isNotEmpty) ...[
                SectionTitle('Needs attention', subtitle: '${problems.length} thing${problems.length == 1 ? '' : 's'} to fix before this works properly'),
                GroupCard(children: [for (final i in problems) _IssueTile(issue: i)]),
              ] else if (controller.setupMode == 'kiosk')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: GroupCard(children: [
                    Tile(
                      icon: Icons.check_circle,
                      color: Semantic.ok,
                      title: 'Everything is set up',
                      subtitle: 'The kiosk is ready. Use the lock above to start it.',
                    ),
                  ]),
                ),
              if (suggestions.isNotEmpty) ...[
                const SectionTitle('Suggestions'),
                GroupCard(children: [for (final i in suggestions) _IssueTile(issue: i)]),
              ],
              const SectionTitle('Right now'),
              GroupCard(children: [
                Tile(
                  icon: s.isNight ? Icons.bedtime_outlined : Icons.wb_sunny_outlined,
                  title: s.isNight ? 'Night' : 'Day',
                  subtitle: (s.cfg['mode'] ?? 'manual') == 'manual'
                      ? 'Brightness is not managed (Display & presence → Brightness control)'
                      : 'Brightness ${s.targetBrightness ?? '–'} of 255 · ${s.cfg['mode']}',
                ),
                Tile(
                  icon: s.presence ? Icons.person : Icons.person_outline,
                  title: s.presence ? 'Someone is near' : 'Nobody near',
                  subtitle: s.cfg['camera_presence'] == true ? 'Camera ${s.cameraActive ? 'running' : 'starting'}' : 'Presence from Home Assistant sensors',
                ),
                Tile(
                  icon: Icons.alarm,
                  title: s.nextAlarmMillis == null ? 'No alarm set' : 'Next alarm ${_clock(DateTime.fromMillisecondsSinceEpoch(s.nextAlarmMillis!))}',
                  subtitle: s.alarmRinging ? 'Ringing now' : null,
                ),
              ]),
              const SectionTitle('Quick actions'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _Action(Icons.dashboard_outlined, 'Open dashboard', () => controller.platform.bringHaToFront()),
                _Action(Icons.wb_twilight, 'Show idle screen', () => controller.platform.showGlance()),
                _Action(Icons.screen_lock_portrait_outlined, 'Screen off', () => controller.platform.sleepScreen()),
                _Action(Icons.search, 'Search settings', () async => openSearch(context, controller)),
              ]),
            ],
          );
        },
      ),
    );
  }
}

String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  @override
  Widget build(BuildContext context) => ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue});
  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final color = issue.severity == Severity.problem ? Semantic.warn : null;
    return Tile(
      icon: issue.icon,
      color: color,
      title: issue.title,
      subtitle: issue.detail,
      trailing: FilledButton.tonal(onPressed: () => issue.fix(context), child: Text(issue.fixLabel)),
    );
  }
}

/// The one control that matters: lock / unlock the kiosk, plus where things stand.
class _Hero extends StatelessWidget {
  const _Hero({required this.controller, required this.link, required this.blocked});
  final AppController controller;
  final LinkState link;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = controller.status;
    final kiosk = controller.setupMode == 'kiosk';
    final locked = s.lockdown;
    final dash = (s.cfg['kiosk_dashboard'] ?? '') as String;
    final scheme = t.colorScheme;
    final bg = locked ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final fg = locked ? scheme.onPrimaryContainer : scheme.onSurface;
    final (linkLabel, linkColor) = switch (link) {
      LinkState.connected => ('Home Assistant connected', Semantic.ok),
      LinkState.connecting => ('Connecting…', Semantic.warn),
      LinkState.authFailed => ('Token rejected', Semantic.bad),
      LinkState.disconnected => ('Not connected', Semantic.bad),
    };
    final (protLabel, protColor) = switch (s.mode) {
      EnforcementMode.deviceOwner => ('Device owner', Semantic.ok),
      EnforcementMode.accessibility => ('Accessibility guard', Semantic.warn),
      EnforcementMode.none => ('No protection', Semantic.bad),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        elevation: 0,
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              Pill(linkLabel, color: linkColor, icon: link == LinkState.connected ? Icons.link : Icons.link_off),
              if (kiosk) Pill(protLabel, color: protColor, icon: Icons.shield_outlined),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Icon(kiosk ? (locked ? Icons.lock : Icons.lock_open) : Icons.tablet_android, size: 44, color: fg),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    kiosk ? (locked ? 'Kiosk locked' : 'Kiosk unlocked') : 'Sensors and alarms',
                    style: t.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    kiosk
                        ? (dash.isEmpty ? 'No dashboard chosen yet' : 'Showing $dash')
                        : 'This device reports sensors and rings alarms for Home Assistant.',
                    style: t.textTheme.bodyMedium?.copyWith(color: fg.withValues(alpha: .8)),
                  ),
                ]),
              ),
            ]),
            if (kiosk) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: locked
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock'),
                        onPressed: () => toggleLockdown(context, controller, false),
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.lock),
                        label: Text(blocked ? 'Finish setup to lock' : 'Lock the kiosk'),
                        onPressed: () => toggleLockdown(context, controller, true),
                      ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
