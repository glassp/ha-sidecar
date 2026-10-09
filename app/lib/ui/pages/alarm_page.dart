import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../timers.dart';

/// Ringing alarm, shown over the lock screen by its own Android activity. Sound is played natively
/// (independent of this UI), so a slow start of the UI never delays the alarm.
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    // started here, not lazily: a `late final` initializer would only run when first read (in dispose)
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final alarm = c.status.ringingAlarm;
    final label = (alarm?['label'] ?? '') as String;
    final isTimer = alarm?['kind'] == 'timer';
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = DateFormat(
      use24 ? 'HH:mm' : 'h:mm',
      context.locale.toString(),
    ).format(DateTime.now());
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false, // the alarm is ended with the buttons only
      child: Theme(
        data: ThemeData.dark(
          useMaterial3: true,
        ).copyWith(scaffoldBackgroundColor: Colors.black),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isTimer ? Icons.timer_outlined : Icons.alarm,
                        size: 40,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isTimer ? 'timers.times_up'.tr() : time,
                        style: t.displayLarge?.copyWith(
                          fontSize: isTimer ? 72 : 112,
                          fontWeight: FontWeight.w200,
                          color: Colors.white,
                        ),
                      ),
                      if (isTimer && alarm?['finished_at'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '+${formatClock(DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch((alarm!['finished_at'] as num).toInt())))} ${'timers.over'.tr()}',
                          style: t.headlineMedium?.copyWith(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        label.isEmpty
                            ? (isTimer ? 'timers.timer'.tr() : 'alarm.ringing'.tr())
                            : label,
                        style: t.headlineSmall?.copyWith(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 56),
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: FilledButton.tonal(
                          onPressed: () async {
                            await c.platform.snoozeAlarm();
                            await c.platform.closeUi('/alarm');
                          },
                          child: Text(
                            isTimer ? 'timers.plus_minute'.tr() : 'alarm.snooze'.tr(),
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: FilledButton(
                          onPressed: () async {
                            await c.platform.stopAlarm();
                            await c.platform.closeUi('/alarm');
                          },
                          child: Text(
                            'alarm.dismiss'.tr(),
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
