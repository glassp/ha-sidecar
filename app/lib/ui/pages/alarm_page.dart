import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';

/// Ringing alarm, shown over the lock screen by its own Android activity. Sound is played natively
/// (independent of this UI), so a slow start of the UI never delays the alarm.
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  late final Timer _clock = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

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
                      const Icon(Icons.alarm, size: 40, color: Colors.white54),
                      const SizedBox(height: 16),
                      Text(
                        time,
                        style: t.displayLarge?.copyWith(
                          fontSize: 112,
                          fontWeight: FontWeight.w200,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label.isEmpty ? 'alarm.ringing'.tr() : label,
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
                            'alarm.snooze'.tr(),
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
