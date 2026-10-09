import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../voice/voice_controller.dart';

/// The assistant's answer screen, shown by its own Android activity over whatever is on screen (a docked
/// bubble over the dashboard is the next step, see docs/VOICE.md).
class VoicePage extends StatelessWidget {
  const VoicePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller.voice;
    return Theme(
      data: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(scaffoldBackgroundColor: Colors.black),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: v,
            builder: (context, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => v.cancel(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _Body(v),
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

class _Body extends StatelessWidget {
  const _Body(this.v);
  final VoiceController v;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final state = v.state;
    final (icon, color, label) = switch (state) {
      VoiceState.listening => (
        Icons.mic,
        scheme.primary,
        'voice.listening'.tr(),
      ),
      VoiceState.thinking => (
        Icons.more_horiz,
        scheme.tertiary,
        'voice.thinking'.tr(),
      ),
      VoiceState.speaking => (
        Icons.volume_up,
        scheme.secondary,
        'voice.speaking'.tr(),
      ),
      VoiceState.error => (Icons.error_outline, scheme.error, _errorTitle(v)),
      VoiceState.idle => (Icons.check, scheme.outline, 'voice.done'.tr()),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 96 + 48 * v.level,
          height: 96 + 48 * v.level,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.18),
            border: Border.all(color: color, width: 3),
          ),
          child: Icon(icon, size: 48, color: color),
        ),
        const SizedBox(height: 24),
        Text(label, style: t.headlineSmall, textAlign: TextAlign.center),
        if (v.transcript.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '“${v.transcript}”',
            style: t.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        if (v.answer.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(v.answer, style: t.titleLarge, textAlign: TextAlign.center),
        ],
        if (state == VoiceState.error && (v.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            v.errorMessage!,
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 32),
        Wrap(
          spacing: 12,
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
            OutlinedButton(
              onPressed: () => v.cancel(),
              child: Text(
                (state == VoiceState.idle || state == VoiceState.error)
                    ? 'voice.close'.tr()
                    : 'voice.cancel'.tr(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _errorTitle(VoiceController v) {
    final key = 'voice.err_${(v.errorCode ?? 'unknown').replaceAll('-', '_')}';
    final text = key.tr();
    return text == key ? 'voice.err_unknown'.tr() : text;
  }
}
