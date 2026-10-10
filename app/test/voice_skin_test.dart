import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_sidecar/voice/voice_skin.dart';

/// WCAG contrast ratio of two colors (1..21).
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a);
  final lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test(
    'the skin ids are what the native config and the Home Assistant select accept',
    () {
      expect(VoiceSkin.ids, [
        'midnight',
        'aurora',
        'sunrise',
        'paper',
        'contrast',
      ]);
      expect(VoiceSkin.ids.toSet().length, VoiceSkin.ids.length);
      expect(VoiceSkin.defaultId, 'midnight');
    },
  );

  test('an unknown or missing skin is the default', () {
    expect(VoiceSkin.byId(null).id, 'midnight');
    expect(VoiceSkin.byId('nope').id, 'midnight');
    expect(VoiceSkin.byId('paper').id, 'paper');
  });

  for (final s in VoiceSkin.all) {
    test('${s.id}: every text is readable on what it sits on', () {
      expect(
        contrast(s.text, s.surface),
        greaterThanOrEqualTo(7),
        reason: 'answer text on the card',
      );
      expect(
        contrast(s.text, s.background),
        greaterThanOrEqualTo(7),
        reason: 'answer text on the page',
      );
      expect(
        contrast(s.textDim, s.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'dim text on the card',
      );
      expect(
        contrast(s.textDim, s.background),
        greaterThanOrEqualTo(4.5),
        reason: 'dim text on the page',
      );
      expect(
        contrast(s.onAccent, s.accent),
        greaterThanOrEqualTo(4.5),
        reason: 'button label',
      );
      expect(
        contrast(s.onUserBubble, s.userBubble),
        greaterThanOrEqualTo(4.5),
        reason: 'what you said',
      );
      expect(
        contrast(s.text, s.assistantBubble),
        greaterThanOrEqualTo(4.5),
        reason: 'the answer bubble',
      );
      expect(
        contrast(s.onErrorContainer, s.errorContainer),
        greaterThanOrEqualTo(4.5),
        reason: 'error text',
      );
    });

    test(
      '${s.id}: the colors that carry meaning stand out from their background',
      () {
        expect(
          contrast(s.accent, s.surface),
          greaterThanOrEqualTo(3),
          reason: 'listening / buttons',
        );
        expect(contrast(s.accent, s.background), greaterThanOrEqualTo(3));
        expect(
          contrast(s.thinking, s.surface),
          greaterThanOrEqualTo(3),
          reason: 'thinking',
        );
        expect(
          contrast(s.error, s.surface),
          greaterThanOrEqualTo(3),
          reason: 'error',
        );
      },
    );

    test('${s.id}: the native card gets #RRGGBB colors', () {
      final m = s.toSnapshot();
      expect(m['id'], s.id);
      for (final e in m.entries.where((e) => e.key != 'id')) {
        expect(e.value, matches(RegExp(r'^#[0-9A-F]{6}$')), reason: e.key);
      }
    });
  }

  test('the theme carries the palette to the widgets', () {
    final t = VoiceSkin.paper.theme;
    expect(t.colorScheme.primary, VoiceSkin.paper.accent);
    expect(t.colorScheme.primaryContainer, VoiceSkin.paper.userBubble);
    expect(t.scaffoldBackgroundColor, VoiceSkin.paper.background);
    expect(t.colorScheme.brightness, Brightness.light);
  });
}
