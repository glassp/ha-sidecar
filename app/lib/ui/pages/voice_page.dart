import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../platform/kiosk_platform.dart';
import '../../voice/voice_controller.dart';
import '../../voice/voice_skin.dart';
import '../timers.dart';
import '../voice_cards.dart';

/// The assistant's screen, shown by its own Android activity over whatever is on screen (a docked bubble over the
/// dashboard is a later step, see docs/VOICE.md). Top: the status and any running timers. Middle: a live waveform of
/// what the microphone hears, then the conversation as chat bubbles (what you said, what the assistant answered).
class VoicePage extends StatelessWidget {
  const VoicePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller.voice;
    // the skin is a setting that can change while the page is open (a long-lived activity): rebuild with the controller
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final skin = VoiceSkin.byId(controller.status.cfg['voice_skin']);
        return Theme(
          data: skin.theme,
          child: Scaffold(
            backgroundColor: skin.background,
            body: SafeArea(
              child: ListenableBuilder(
                listenable: Listenable.merge([v, controller]),
                builder: (context, _) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => v.endConversation(),
                  child: Column(
                    children: [
                      _TopBar(v),
                      _Timers(controller.status.timers),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 8,
                              ),
                              reverse: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _Wave(v),
                                  _WaitBar(v),
                                  const SizedBox(height: 24),
                                  _Conversation(v),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _VolumeRow(v),
                      _Actions(v),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- top: status and close ---------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar(this.v);
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (v.state) {
      VoiceState.listening => (
        v.followUp ? Icons.forum_outlined : Icons.mic,
        scheme.primary,
        v.followUp ? 'voice.listening_followup'.tr() : 'voice.listening'.tr(),
      ),
      VoiceState.thinking => (
        Icons.auto_awesome,
        scheme.tertiary,
        'voice.thinking'.tr(),
      ),
      VoiceState.speaking => (
        Icons.volume_up,
        scheme.secondary,
        'voice.speaking'.tr(),
      ),
      VoiceState.error => (
        Icons.error_outline,
        scheme.error,
        'voice.error_chip'.tr(),
      ),
      VoiceState.idle => (
        Icons.check_circle_outline,
        scheme.outline,
        'voice.done'.tr(),
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          Chip(
            avatar: Icon(icon, size: 18, color: color),
            label: Text(label),
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            backgroundColor: color.withValues(alpha: 0.12),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'voice.close'.tr(),
            onPressed: () => v.endConversation(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

// --- timers ---------------------------------------------------------------------------------------

class _Timers extends StatelessWidget {
  const _Timers(this.timers);
  final List<TimerSpec> timers;

  @override
  Widget build(BuildContext context) {
    if (timers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SecondTicker(
        builder: (context, now) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final t in timers) TimerPill(timer: t, now: now)],
        ),
      ),
    );
  }
}

/// A running timer or stopwatch as a pill: a ring that empties as a countdown runs down, the time, the label.
class TimerPill extends StatelessWidget {
  const TimerPill({super.key, required this.timer, required this.now});
  final TimerSpec timer;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = t.colorScheme;
    final over = timer.finished;
    final left = timer.isCountdown && timer.durationMs > 0
        ? (timer.shown(now).inMilliseconds / timer.durationMs).clamp(0.0, 1.0)
        : null;
    final color = over
        ? s.error
        : timer.paused
        ? s.onSurfaceVariant
        : s.primary;
    return Container(
      key: ValueKey('timer-pill-${timer.id}'),
      padding: const EdgeInsets.fromLTRB(10, 8, 20, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: over ? 1 : left,
                  strokeWidth: 4,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.2),
                ),
                Icon(
                  over
                      ? Icons.notifications_active
                      : timer.paused
                      ? Icons.pause
                      : timer.isCountdown
                      ? Icons.timer_outlined
                      : Icons.directions_run,
                  size: 20,
                  color: color,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timerText(timer, now),
                style: t.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: over ? s.error : null,
                ),
              ),
              Text(
                timerTitle(timer),
                style: t.textTheme.bodySmall?.copyWith(
                  color: s.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- waveform -------------------------------------------------------------------------------------

/// Bars that follow the microphone level while listening, pulse while the assistant thinks and ripple while it speaks.
class _Wave extends StatefulWidget {
  const _Wave(this.v);
  final VoiceController v;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final v = widget.v;
    final color = switch (v.state) {
      VoiceState.listening => s.primary,
      VoiceState.thinking => s.tertiary,
      VoiceState.speaking => s.secondary,
      VoiceState.error => s.error,
      VoiceState.idle => s.outline,
    };
    return SizedBox(
      height: 110,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => CustomPaint(
          size: const Size(double.infinity, 110),
          painter: _WavePainter(
            state: v.state,
            levels: List.of(v.levels),
            phase: _anim.value,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.state,
    required this.levels,
    required this.phase,
    required this.color,
  });
  final VoiceState state;
  final List<double> levels;
  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = VoiceController.levelHistory;
    final gap = size.width / n;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.min(10, gap * 0.55);
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      double a; // 0..1
      switch (state) {
        case VoiceState.listening:
          // newest level on the right; before the first frames arrive the bars rest
          final idx = i - (n - levels.length);
          a = idx >= 0 ? math.min(1.0, levels[idx] * 1.6) : 0;
          a = math.max(a, 0.04 + 0.02 * math.sin(phase * 2 * math.pi + i));
        case VoiceState.thinking:
          a =
              0.08 +
              0.1 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi - i * 0.35));
        case VoiceState.speaking:
          final envelope =
              0.5 + 0.5 * math.sin(i / n * math.pi); // taller in the middle
          a =
              envelope *
              (0.25 +
                  0.55 *
                      (0.5 +
                          0.5 * math.sin(phase * 2 * math.pi * 2 - i * 0.6)));
        case VoiceState.error:
        case VoiceState.idle:
          a = 0.04;
      }
      final h = math.max(6.0, a * size.height);
      final x = gap * (i + 0.5);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true; // animated
}

/// While the tablet waits for you to start speaking: a bar that drains over the time left before the conversation ends.
class _WaitBar extends StatelessWidget {
  const _WaitBar(this.v);
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final show = v.waitingForSpeech && v.state == VoiceState.listening;
    final s = Theme.of(context).colorScheme;
    return SizedBox(
      height: 22,
      child: show
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: TweenAnimationBuilder<double>(
                key: ValueKey('wait-${v.session}'),
                tween: Tween(begin: 1, end: 0),
                duration: v.speechWindow,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    color: s.primary.withValues(alpha: 0.7),
                    backgroundColor: s.primary.withValues(alpha: 0.15),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

// --- conversation ---------------------------------------------------------------------------------

class _Conversation extends StatelessWidget {
  const _Conversation(this.v);
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final turns = v.turns;
    final shown = turns.length > 3 ? turns.sublist(turns.length - 3) : turns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++)
          _TurnView(
            turn: shown[i],
            current: identical(shown[i], turns.last),
            v: v,
          ),
      ],
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn, required this.current, required this.v});
  final VoiceTurn turn;
  final bool current;
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final listening = current && v.state == VoiceState.listening;
    final thinking = current && v.state == VoiceState.thinking;
    final speaking = current && v.state == VoiceState.speaking;
    final failed = current && v.state == VoiceState.error;
    return Opacity(
      opacity: current ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (turn.user.isNotEmpty || listening)
              Align(
                alignment: Alignment.centerRight,
                child: _Bubble(
                  key: const ValueKey('bubble-user'),
                  color: s.primaryContainer,
                  radius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                    bottomLeft: Radius.circular(22),
                    bottomRight: Radius.circular(5),
                  ),
                  child: turn.user.isEmpty
                      ? const _Dots()
                      : Text(
                          turn.user,
                          style: t.titleMedium?.copyWith(
                            color: s.onPrimaryContainer,
                          ),
                        ),
                ),
              ),
            if (turn.user.isNotEmpty || listening) const SizedBox(height: 8),
            if (turn.assistant.isNotEmpty || thinking || speaking || failed)
              Align(
                alignment: Alignment.centerLeft,
                child: _Bubble(
                  key: ValueKey(failed ? 'bubble-error' : 'bubble-assistant'),
                  color: failed ? s.errorContainer : s.surfaceContainerHighest,
                  radius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                    bottomLeft: Radius.circular(5),
                    bottomRight: Radius.circular(22),
                  ),
                  child: failed
                      ? _ErrorText(v)
                      : turn.assistant.isEmpty
                      ? const _Dots()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(turn.assistant, style: t.titleLarge),
                            ),
                            if (speaking) ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.graphic_eq,
                                color: s.secondary,
                                size: 22,
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ResultCards(turn.cards),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.color,
    required this.radius,
    required this.child,
  });
  final Color color;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: math.min(560, MediaQuery.sizeOf(context).width * 0.8),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: child,
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.v);
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final key = 'voice.err_${(v.errorCode ?? 'unknown').replaceAll('-', '_')}';
    final text = key.tr();
    final title = text == key ? 'voice.err_unknown'.tr() : text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.titleMedium?.copyWith(color: s.onErrorContainer)),
        if ((v.errorMessage ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              v.errorMessage!,
              style: t.bodyMedium?.copyWith(color: s.onErrorContainer),
            ),
          ),
      ],
    );
  }
}

/// Three dots that pulse one after the other: someone is about to say something.
class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Opacity(
                opacity:
                    0.3 +
                    0.7 *
                        (0.5 +
                            0.5 * math.sin((_c.value * 2 - i * 0.3) * math.pi)),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- actions ----------------------------------------------------------------------------------------

class _Actions extends StatelessWidget {
  const _Actions(this.v);
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final state = v.state;
    final ended = state == VoiceState.idle || state == VoiceState.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (state == VoiceState.listening)
            FilledButton.icon(
              onPressed: v.stopListening,
              icon: const Icon(Icons.stop),
              label: Text('voice.done_talking'.tr()),
            ),
          if (state == VoiceState.error && v.errorCode == 'mic_permission')
            FilledButton.icon(
              onPressed: v.platform.requestMicPermission,
              icon: const Icon(Icons.mic_none),
              label: Text('voice.allow_mic'.tr()),
            ),
          if (ended)
            FilledButton.tonalIcon(
              key: const ValueKey('voice-again'),
              onPressed: () => v.listen(continuing: true),
              icon: const Icon(Icons.mic),
              label: Text('voice.talk_again'.tr()),
            ),
          OutlinedButton(
            key: const ValueKey('voice-end'),
            onPressed: () => v.endConversation(),
            child: Text(
              ended ? 'voice.close'.tr() : 'voice.end_conversation'.tr(),
            ),
          ),
        ],
      ),
    );
  }
}

// --- volume: the voice volume, next to the answer -----------------------------------------------

class _VolumeRow extends StatelessWidget {
  const _VolumeRow(this.v);
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final volume = v.volume;
    if (volume == null || v.state == VoiceState.error) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Row(
            children: [
              Icon(
                volume == 0
                    ? Icons.volume_off
                    : (volume < 40 ? Icons.volume_down : Icons.volume_up),
                color: scheme.onSurfaceVariant,
                size: 22,
              ),
              Expanded(
                child: Slider(
                  key: const Key('voice-volume'),
                  value: volume.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (x) => v.changeVolume(x.round()),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '$volume %',
                  textAlign: TextAlign.end,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
