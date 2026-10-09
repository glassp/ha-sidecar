import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../platform/kiosk_platform.dart';
import 'design.dart';

/// `1:05:09` / `5:09` / `0:09`.
String formatClock(Duration d) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// Rebuilds every second while [active] (timers tick without polling the device).
class SecondTicker extends StatefulWidget {
  const SecondTicker({super.key, required this.builder, this.active = true});
  final Widget Function(BuildContext context, DateTime now) builder;
  final bool active;

  @override
  State<SecondTicker> createState() => _SecondTickerState();
}

class _SecondTickerState extends State<SecondTicker> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SecondTicker old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && _t == null) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.active) {
      _t?.cancel();
      _t = null;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

String timerTitle(TimerSpec t) => t.label.isNotEmpty
    ? t.label
    : (t.isCountdown ? 'timers.timer'.tr() : 'timers.stopwatch'.tr());

/// What a timer shows: `+0:12` of overtime once a countdown is over, otherwise the clock.
String timerText(TimerSpec t, DateTime now) =>
    t.finished ? '+${formatClock(t.overtime(now))}' : formatClock(t.shown(now));

/// One timer row: big live time, label, pause/resume, +1 min (countdowns) and cancel.
class TimerTile extends StatelessWidget {
  const TimerTile({super.key, required this.controller, required this.timer, required this.now});
  final AppController controller;
  final TimerSpec timer;
  final DateTime now;

  Future<void> _do(Future<void> Function() action) async {
    await action();
    await controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = controller.platform;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            timer.isCountdown ? Icons.timer_outlined : Icons.directions_run,
            color: t.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timerText(timer, now),
                  style: t.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w300,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: timer.paused
                        ? t.colorScheme.onSurfaceVariant
                        : timer.finished
                        ? t.colorScheme.error
                        : null,
                  ),
                ),
                Text(
                  [
                    timerTitle(timer),
                    if (timer.paused) 'timers.paused'.tr(),
                    if (timer.finished) 'timers.over'.tr(),
                    if (timer.isCountdown) 'timers.of'.tr(args: [formatClock(Duration(milliseconds: timer.durationMs))]),
                  ].join(' · '),
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (timer.isCountdown)
            TextButton(
              onPressed: () => _do(() => p.adjustTimer(timer.id, const Duration(minutes: 1))),
              child: Text('timers.plus_minute'.tr()),
            ),
          IconButton(
            tooltip: timer.paused ? 'timers.resume'.tr() : 'timers.pause'.tr(),
            onPressed: timer.finished
                ? null
                : () => _do(() => timer.paused ? p.resumeTimer(timer.id) : p.pauseTimer(timer.id)),
            icon: Icon(timer.paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: 'timers.cancel'.tr(),
            onPressed: () => _do(() => p.cancelTimer(timer.id)),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Sheet to start a labeled countdown.
Future<void> startTimerSheet(BuildContext context, AppController c) async {
  final label = TextEditingController();
  final h = TextEditingController(text: '0');
  final m = TextEditingController(text: '10');
  final s = TextEditingController(text: '0');
  var error = false;

  int n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  void preset(int minutes) {
    h.text = '${minutes ~/ 60}';
    m.text = '${minutes % 60}';
    s.text = '0';
  }

  final start = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget field(TextEditingController ctl, String unit) => Expanded(
          child: TextField(
            controller: ctl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              suffixText: unit,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('timers.new'.tr(), style: Theme.of(ctx).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextField(
                  controller: label,
                  maxLength: 64,
                  decoration: InputDecoration(
                    labelText: 'timers.label'.tr(),
                    hintText: 'timers.label_hint'.tr(),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    field(h, 'h'),
                    const SizedBox(width: 8),
                    field(m, 'min'),
                    const SizedBox(width: 8),
                    field(s, 's'),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final min in [1, 5, 10, 15, 30, 45, 60])
                      ActionChip(
                        label: Text(min == 60 ? '1 h' : '$min min'),
                        onPressed: () => setState(() => preset(min)),
                      ),
                  ],
                ),
                if (error)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'timers.invalid'.tr(),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
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
                      onPressed: () {
                        final total = n(h) * 3600 + n(m) * 60 + n(s);
                        if (total < 1 || total > 99 * 3600) {
                          setState(() => error = true);
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      child: Text('timers.start'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (start == true) {
    await c.platform.startTimer(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      label: label.text.trim(),
      duration: Duration(seconds: n(h) * 3600 + n(m) * 60 + n(s)),
    );
    await c.refresh();
  }
}

Future<void> startStopwatch(BuildContext context, AppController c) async {
  final label = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('timers.new_stopwatch'.tr()),
      content: TextField(
        controller: label,
        maxLength: 64,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'timers.label'.tr(),
          hintText: 'timers.stopwatch_hint'.tr(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('common.cancel'.tr())),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('timers.start'.tr())),
      ],
    ),
  );
  if (go == true) {
    await c.platform.startTimer(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      label: label.text.trim(),
      kind: 'countup',
    );
    await c.refresh();
  }
}

/// Timers section for the alarms tab.
class TimersSection extends StatelessWidget {
  const TimersSection({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final timers = controller.status.timers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => startTimerSheet(context, controller),
                icon: const Icon(Icons.timer_outlined),
                label: Text('timers.add'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => startStopwatch(context, controller),
                icon: const Icon(Icons.directions_run),
                label: Text('timers.add_stopwatch'.tr()),
              ),
            ),
          ],
        ),
        if (timers.isNotEmpty) ...[
          const SizedBox(height: 12),
          SecondTicker(
            builder: (context, now) => GroupCard(
              children: [
                for (final t in timers)
                  TimerTile(controller: controller, timer: t, now: now),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
