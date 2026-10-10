import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../timers.dart';

/// At a glance: clock, date, next alarm and a few Home Assistant values on pure black.
/// Any touch dismisses it; presence dismisses it from the native side.
class GlancePage extends StatefulWidget {
  const GlancePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<GlancePage> createState() => _GlancePageState();
}

class _GlancePageState extends State<GlancePage> {
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

  Future<void> _dismiss() async {
    await widget.controller.platform.reportTouch();
    await widget.controller.platform.closeUi('/glance');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.status;
    final locale = context.locale.toString();
    final now = DateTime.now();
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = DateFormat(use24 ? 'HH:mm' : 'h:mm', locale).format(now);
    final date = DateFormat.MMMMEEEEd(locale).format(now);
    final next = s.nextAlarmMillis;
    final items = s.glanceItems.take(9).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Theme(
        data: ThemeData.dark(
          useMaterial3: true,
        ).copyWith(scaffoldBackgroundColor: Colors.black),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            onPanDown: (_) => _dismiss(),
            child: SizedBox.expand(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // one line at any width: full size on a tablet, scaled down on a phone
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              time,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontSize: 150,
                                fontWeight: FontWeight.w200,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white70,
                          ),
                        ),
                        if (next != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.alarm,
                                size: 20,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat(
                                  use24 ? 'EEE HH:mm' : 'EEE h:mm a',
                                  locale,
                                ).format(
                                  DateTime.fromMillisecondsSinceEpoch(next),
                                ),
                                style: const TextStyle(
                                  fontSize: 20,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (s.timers.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          for (final tm in s.timers.take(4))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tm.isCountdown
                                        ? Icons.timer_outlined
                                        : Icons.directions_run,
                                    size: 28,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    timerText(tm, now),
                                    style: TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w300,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                      color: tm.paused
                                          ? Colors.white38
                                          : tm.finished
                                          ? Colors.redAccent
                                          : Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Flexible(
                                    child: Text(
                                      timerTitle(tm),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (items.isNotEmpty) ...[
                          const SizedBox(height: 48),
                          Wrap(
                            spacing: 40,
                            runSpacing: 24,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final i in items)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${i['value']}',
                                      style: const TextStyle(
                                        fontSize: 38,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${i['name']}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
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
