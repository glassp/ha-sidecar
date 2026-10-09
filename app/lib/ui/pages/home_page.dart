import 'package:beamer/beamer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../ha/sidecar_client.dart';
import '../../health.dart';
import '../../platform/kiosk_platform.dart';
import '../design.dart';
import '../dialogs.dart';
import 'section_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ValueListenableBuilder<LinkState>(
        valueListenable:
            controller.link ?? ValueNotifier(LinkState.disconnected),
        builder: (context, link, _) {
          final s = controller.status;
          final issues = computeIssues(
            controller,
            link,
            (ctx, id) => openEntry(ctx, controller, id),
          );
          final problems = issues
              .where((i) => i.severity == Severity.problem)
              .toList();
          final suggestions = issues
              .where((i) => i.severity == Severity.suggestion)
              .toList();
          return AppPage(
            title: 'app.name'.tr(),
            actions: [searchAction(context, controller)],
            children: [
              _Hero(
                controller: controller,
                link: link,
                blocked: problems.isNotEmpty,
              ),
              if (problems.isNotEmpty) ...[
                SectionTitle(
                  'home.needs_attention'.tr(),
                  subtitle: 'home.needs_attention_sub'.plural(problems.length),
                ),
                GroupCard(
                  children: [for (final i in problems) _IssueTile(issue: i)],
                ),
              ] else if (controller.setupMode == 'kiosk')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: GroupCard(
                    children: [
                      Tile(
                        icon: Icons.check_circle,
                        color: Semantic.ok,
                        title: 'home.all_set'.tr(),
                        subtitle: 'home.all_set_desc'.tr(),
                      ),
                    ],
                  ),
                ),
              if (suggestions.isNotEmpty) ...[
                SectionTitle('home.suggestions'.tr()),
                GroupCard(
                  children: [for (final i in suggestions) _IssueTile(issue: i)],
                ),
              ],
              SectionTitle('home.right_now'.tr()),
              GroupCard(
                children: [
                  Tile(
                    icon: s.isNight
                        ? Icons.bedtime_outlined
                        : Icons.wb_sunny_outlined,
                    title: s.isNight ? 'home.night'.tr() : 'home.day'.tr(),
                    subtitle: (s.cfg['mode'] ?? 'manual') == 'manual'
                        ? 'home.brightness_unmanaged'.tr()
                        : 'home.brightness_target'.tr(
                            namedArgs: {
                              'level': '${s.targetBrightness ?? '–'}',
                              'mode': 'mode.${s.cfg['mode']}'.tr(),
                            },
                          ),
                  ),
                  Tile(
                    icon: s.presence ? Icons.person : Icons.person_outline,
                    title: s.presence
                        ? 'home.someone_near'.tr()
                        : 'home.nobody_near'.tr(),
                    subtitle: s.cfg['camera_presence'] == true
                        ? (s.cameraActive
                              ? 'home.camera_running'.tr()
                              : 'home.camera_starting'.tr())
                        : 'home.presence_from_ha'.tr(),
                  ),
                  Tile(
                    icon: Icons.alarm,
                    title: s.nextAlarmMillis == null
                        ? 'home.no_alarm'.tr()
                        : 'home.next_alarm'.tr(
                            namedArgs: {
                              'time': _clock(
                                DateTime.fromMillisecondsSinceEpoch(
                                  s.nextAlarmMillis!,
                                ),
                              ),
                            },
                          ),
                    subtitle: s.alarmRinging ? 'home.ringing'.tr() : null,
                  ),
                ],
              ),
              SectionTitle('home.quick_actions'.tr()),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Action(
                    Icons.dashboard_outlined,
                    'home.qa_dashboard'.tr(),
                    () => controller.platform.bringHaToFront(),
                  ),
                  _Action(
                    Icons.wb_twilight,
                    'home.qa_idle'.tr(),
                    () => controller.platform.showGlance(),
                  ),
                  _Action(
                    Icons.screen_lock_portrait_outlined,
                    'home.qa_screen_off'.tr(),
                    () => controller.platform.sleepScreen(),
                  ),
                  _Action(
                    Icons.search,
                    'search.title'.tr(),
                    () async => context.beamToNamed('/search', stacked: false),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

String _clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onPressed: onTap,
  );
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
      trailing: FilledButton.tonal(
        onPressed: () => issue.fix(context),
        child: Text(issue.fixLabel),
      ),
    );
  }
}

/// The one control that matters: lock / unlock the kiosk, plus where things stand.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.controller,
    required this.link,
    required this.blocked,
  });
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
      LinkState.connected => ('home.link_connected'.tr(), Semantic.ok),
      LinkState.connecting => ('link.connecting'.tr(), Semantic.warn),
      LinkState.authFailed => ('link.rejected'.tr(), Semantic.bad),
      LinkState.disconnected => ('link.disconnected'.tr(), Semantic.bad),
    };
    final (protLabel, protColor) = switch (s.mode) {
      EnforcementMode.deviceOwner => ('prot.device_owner'.tr(), Semantic.ok),
      EnforcementMode.accessibility => (
        'prot.accessibility'.tr(),
        Semantic.warn,
      ),
      EnforcementMode.none => ('prot.none'.tr(), Semantic.bad),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        elevation: 0,
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    linkLabel,
                    color: linkColor,
                    icon: link == LinkState.connected
                        ? Icons.link
                        : Icons.link_off,
                  ),
                  if (kiosk)
                    Pill(
                      protLabel,
                      color: protColor,
                      icon: Icons.shield_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(
                    kiosk
                        ? (locked ? Icons.lock : Icons.lock_open)
                        : Icons.tablet_android,
                    size: 44,
                    color: fg,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kiosk
                              ? (locked
                                    ? 'home.kiosk_locked'.tr()
                                    : 'home.kiosk_unlocked'.tr())
                              : 'home.extras_title'.tr(),
                          style: t.textTheme.headlineSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          kiosk
                              ? (dash.isEmpty
                                    ? 'home.no_dashboard'.tr()
                                    : 'home.showing'.tr(
                                        namedArgs: {'path': dash},
                                      ))
                              : 'home.extras_desc'.tr(),
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: fg.withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (kiosk) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: locked
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.lock_open),
                          label: Text('home.unlock'.tr()),
                          onPressed: () =>
                              toggleLockdown(context, controller, false),
                        )
                      : FilledButton.icon(
                          icon: const Icon(Icons.lock),
                          label: Text(
                            blocked
                                ? 'home.finish_setup'.tr()
                                : 'home.lock'.tr(),
                          ),
                          onPressed: () =>
                              toggleLockdown(context, controller, true),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
