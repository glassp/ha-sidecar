import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../platform/kiosk_platform.dart';
import '../design.dart';
import '../timers.dart';
import 'section_page.dart';

List<String> _dayNames() => [
  for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
    'day.$d'.tr(),
];

String _two(int v) => v.toString().padLeft(2, '0');

class AlarmsPage extends StatelessWidget {
  const AlarmsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final alarms = [...controller.alarms]
          ..sort(
            (a, b) =>
                (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
          );
        final t = Theme.of(context);
        return AppPage(
          title: 'alarms.title'.tr(),
          actions: [searchAction(context, controller)],
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => editAlarm(context, controller, null),
            icon: const Icon(Icons.add_alarm),
            label: Text('alarms.add'.tr()),
          ),
          children: [
            HelpText('alarms.intro'.tr()),
            TimersSection(controller: controller),
            const SizedBox(height: 16),
            _MuteCard(controller: controller),
            const SizedBox(height: 8),
            if (alarms.isEmpty) ...[
              const SizedBox(height: 64),
              Icon(
                Icons.alarm_off,
                size: 56,
                color: t.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'alarms.empty_title'.tr(),
                textAlign: TextAlign.center,
                style: t.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'alarms.empty_desc'.tr(),
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium,
              ),
            ] else ...[
              const SizedBox(height: 8),
              GroupCard(
                children: [
                  for (final a in alarms)
                    Dismissible(
                      key: ValueKey(a.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Semantic.bad,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      onDismissed: (_) async {
                        await controller.platform.removeAlarm(a.id);
                        await controller.refresh();
                      },
                      child: InkWell(
                        onTap: () => editAlarm(context, controller, a),
                        onLongPress: a.days.isEmpty
                            ? null
                            : () async {
                                await controller.platform.skipNextAlarm(a.id);
                                await controller.refresh();
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_two(a.hour)}:${_two(a.minute)}',
                                      style: t.textTheme.displaySmall?.copyWith(
                                        fontWeight: FontWeight.w300,
                                        color: a.enabled
                                            ? null
                                            : t.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      [
                                        if (a.label.isNotEmpty) a.label,
                                        a.days.isEmpty
                                            ? 'alarms.once'.tr()
                                            : (a.days.length == 7
                                                  ? 'alarms.every_day'.tr()
                                                  : a.days
                                                        .map(
                                                          (d) =>
                                                              _dayNames()[d -
                                                                  1],
                                                        )
                                                        .join(' ')),
                                        if (a.skipNext) 'alarms.skipping'.tr(),
                                      ].join(' · '),
                                      style: t.textTheme.bodyMedium?.copyWith(
                                        color: t.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: a.enabled,
                                onChanged: (v) async {
                                  await controller.platform.upsertAlarm(
                                    AlarmSpec(
                                      id: a.id,
                                      hour: a.hour,
                                      minute: a.minute,
                                      days: a.days,
                                      label: a.label,
                                      enabled: v,
                                      snoozeMinutes: a.snoozeMinutes,
                                    ),
                                  );
                                  await controller.refresh();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              HelpText('alarms.swipe_hint'.tr()),
            ],
          ],
        );
      },
    );
  }
}

Future<void> editAlarm(
  BuildContext context,
  AppController c,
  AlarmSpec? existing,
) async {
  var time = TimeOfDay(
    hour: existing?.hour ?? TimeOfDay.now().hour,
    minute: existing?.minute ?? TimeOfDay.now().minute,
  );
  final label = TextEditingController(text: existing?.label ?? '');
  final days = {...?existing?.days};
  var snooze = existing?.snoozeMinutes ?? 9;

  final save = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existing == null ? 'alarms.new'.tr() : 'alarms.edit'.tr(),
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: time,
                  );
                  if (picked != null) setState(() => time = picked);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${_two(time.hour)}:${_two(time.minute)}',
                    style: Theme.of(ctx).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: label,
                decoration: InputDecoration(
                  labelText: 'alarms.label'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'alarms.repeat'.tr(),
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(
                      label: Text(_dayNames()[i - 1]),
                      selected: days.contains(i),
                      onSelected: (v) =>
                          setState(() => v ? days.add(i) : days.remove(i)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                days.isEmpty
                    ? 'alarms.rings_once'.tr()
                    : 'alarms.repeats_days'.tr(),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('alarms.snooze'.tr())),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 5, label: Text('5 min')),
                      ButtonSegment(value: 9, label: Text('9 min')),
                      ButtonSegment(value: 15, label: Text('15 min')),
                    ],
                    selected: {snooze},
                    onSelectionChanged: (v) => setState(() => snooze = v.first),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('common.save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (save == true) {
    await c.platform.upsertAlarm(
      AlarmSpec(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        hour: time.hour,
        minute: time.minute,
        days: days.toList()..sort(),
        label: label.text.trim(),
        enabled: true,
        snoozeMinutes: snooze,
      ),
    );
    await c.refresh();
  }
}

/// Silences every alarm for a while (e.g. while away) without deleting them; HA can do the same.
class _MuteCard extends StatelessWidget {
  const _MuteCard({required this.controller});
  final AppController controller;

  Future<void> _toggle(BuildContext context, bool on) async {
    final p = controller.platform;
    if (!on) {
      await p.setAlarmsMuted();
    } else {
      final choice = await showModalBottomSheet<Duration?>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('alarms.mute_for'.tr()),
                titleTextStyle: Theme.of(ctx).textTheme.titleMedium,
              ),
              ListTile(
                title: Text('alarms.mute_day'.tr()),
                onTap: () => Navigator.pop(ctx, const Duration(days: 1)),
              ),
              ListTile(
                title: Text('alarms.mute_week'.tr()),
                onTap: () => Navigator.pop(ctx, const Duration(days: 7)),
              ),
              ListTile(
                title: Text('alarms.mute_forever'.tr()),
                onTap: () => Navigator.pop(ctx, Duration.zero),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      await p.setAlarmsMuted(
        until: choice == Duration.zero ? null : DateTime.now().add(choice),
        forever: choice == Duration.zero,
      );
    }
    await controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    final until = s.alarmsMutedUntil;
    return GroupCard(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_paused_outlined),
          title: Text('alarms.mute'.tr()),
          subtitle: Text(
            !s.alarmsMuted
                ? 'alarms.mute_desc'.tr()
                : until == null
                ? 'alarms.muted_forever'.tr()
                : 'alarms.muted_until'.tr(
                    args: [
                      DateFormat.MMMEd(context.locale.toString())
                          .add_Hm()
                          .format(DateTime.fromMillisecondsSinceEpoch(until)),
                    ],
                  ),
          ),
          value: s.alarmsMuted,
          onChanged: (v) => _toggle(context, v),
        ),
      ],
    );
  }
}
