import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../design.dart';

/// Leaves the locked kiosk. Shown full screen by its own Android activity (over the locked HA app).
class PinPage extends StatefulWidget {
  const PinPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  String _pin = '';
  String? _error;
  Timer? _tick;
  int _lockedMs = 0;
  DateTime? _lockedUntil;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _digit(String d) {
    if (_lockedMs > 0 || _pin.length >= 12) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_pin.length < 4 || _lockedMs > 0) return;
    final r = await widget.controller.platform.unlockWithPin(_pin);
    if (!mounted) return;
    if (r == 0) {
      await widget.controller.platform.closeUi('/pin');
      return;
    }
    setState(() {
      _pin = '';
      if (r == -1) {
        _error = 'pin.page.wrong'.tr();
      } else {
        _lockedUntil = DateTime.now().add(Duration(milliseconds: r));
        _lockedMs = r;
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
          final left = _lockedUntil!.difference(DateTime.now()).inMilliseconds;
          if (!mounted) return;
          setState(() => _lockedMs = left > 0 ? left : 0);
          if (left <= 0) _tick?.cancel();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final locked = _lockedMs > 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.controller.platform.closeUi('/pin');
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconBadge(
                      locked ? Icons.timer_outlined : Icons.lock_outline,
                      size: 64,
                      color: locked ? Semantic.warn : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'pin.page.title'.tr(),
                      style: t.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 28,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _pin.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: CircleAvatar(
                                radius: 7,
                                backgroundColor: t.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          locked
                              ? 'pin.page.locked'.tr(
                                  namedArgs: {
                                    'seconds': '${(_lockedMs / 1000).ceil()}',
                                  },
                                )
                              : (_error ?? ''),
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: locked ? Semantic.warn : Semantic.bad,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    for (final row in const [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                    ])
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final d in row)
                            _Key(
                              label: d,
                              onTap: locked ? null : () => _digit(d),
                            ),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Key(
                          icon: Icons.backspace_outlined,
                          onTap: locked ? null : _backspace,
                        ),
                        _Key(
                          label: '0',
                          onTap: locked ? null : () => _digit('0'),
                        ),
                        _Key(
                          icon: Icons.check,
                          filled: true,
                          onTap: locked || _pin.length < 4 ? null : _submit,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          widget.controller.platform.closeUi('/pin'),
                      child: Text('common.cancel'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.onTap, this.filled = false});
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = label != null
        ? Text(label!, style: Theme.of(context).textTheme.headlineSmall)
        : Icon(icon, size: 26);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 84,
        height: 72,
        child: filled
            ? FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onPressed: onTap,
                child: child,
              )
            : FilledButton.tonal(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onPressed: onTap,
                child: child,
              ),
      ),
    );
  }
}
