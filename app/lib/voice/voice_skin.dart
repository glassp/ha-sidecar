import 'package:flutter/material.dart';

/// A look for the voice screen and the docked card: one palette, used by the Flutter page (as its theme) and sent to the native
/// card (as `#RRGGBB` strings), so both always match. Add a skin by adding an entry to [VoiceSkin.all].
class VoiceSkin {
  const VoiceSkin({
    required this.id,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.text,
    required this.textDim,
    required this.accent,
    required this.onAccent,
    required this.secondary,
    required this.thinking,
    required this.error,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.userBubble,
    required this.onUserBubble,
    required this.assistantBubble,
    required this.outline,
  });

  final String id;
  final Brightness brightness;

  /// Behind the full-screen page.
  final Color background;

  /// The docked card.
  final Color surface;
  final Color text;
  final Color textDim;

  /// Listening, buttons, sliders, rings.
  final Color accent;
  final Color onAccent;

  /// Speaking.
  final Color secondary;
  final Color thinking;
  final Color error;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color userBubble;
  final Color onUserBubble;
  final Color assistantBubble;
  final Color outline;

  static const defaultId = 'midnight';

  static const midnight = VoiceSkin(
    id: 'midnight',
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF201C27),
    text: Color(0xFFE6E1EC),
    textDim: Color(0xFFCAC4D0),
    accent: Color(0xFFCFBCFF),
    onAccent: Color(0xFF381E72),
    secondary: Color(0xFFCCC2DC),
    thinking: Color(0xFFEFB8C8),
    error: Color(0xFFF2B8B5),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    userBubble: Color(0xFF4F378B),
    onUserBubble: Color(0xFFEADDFF),
    assistantBubble: Color(0xFF36343B),
    outline: Color(0xFF4A4458),
  );

  static const aurora = VoiceSkin(
    id: 'aurora',
    brightness: Brightness.dark,
    background: Color(0xFF031512),
    surface: Color(0xFF0D2723),
    text: Color(0xFFE0F2EE),
    textDim: Color(0xFFA6C7C0),
    accent: Color(0xFF5EEAD4),
    onAccent: Color(0xFF003731),
    secondary: Color(0xFF7DD3C0),
    thinking: Color(0xFFA7F3D0),
    error: Color(0xFFFCA5A5),
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: Color(0xFFFEE2E2),
    userBubble: Color(0xFF0F766E),
    onUserBubble: Color(0xFFCCFBF1),
    assistantBubble: Color(0xFF173631),
    outline: Color(0xFF2B5A52),
  );

  static const sunrise = VoiceSkin(
    id: 'sunrise',
    brightness: Brightness.dark,
    background: Color(0xFF130B05),
    surface: Color(0xFF2A1B10),
    text: Color(0xFFFDEBD3),
    textDim: Color(0xFFD9BC9A),
    accent: Color(0xFFFDBA74),
    onAccent: Color(0xFF4A2200),
    secondary: Color(0xFFF5C99B),
    thinking: Color(0xFFFDE68A),
    error: Color(0xFFFCA5A5),
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: Color(0xFFFEE2E2),
    userBubble: Color(0xFF9A3412),
    onUserBubble: Color(0xFFFFEDD5),
    assistantBubble: Color(0xFF3B2716),
    outline: Color(0xFF6B4A2E),
  );

  static const paper = VoiceSkin(
    id: 'paper',
    brightness: Brightness.light,
    background: Color(0xFFF7F4EE),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1F1B16),
    textDim: Color(0xFF5F5A52),
    accent: Color(0xFF6750A4),
    onAccent: Color(0xFFFFFFFF),
    secondary: Color(0xFF7D6BB0),
    thinking: Color(0xFF8E4A6B),
    error: Color(0xFFB3261E),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    userBubble: Color(0xFF6750A4),
    onUserBubble: Color(0xFFFFFFFF),
    assistantBubble: Color(0xFFECE6F0),
    outline: Color(0xFFCAC4D0),
  );

  static const contrast = VoiceSkin(
    id: 'contrast',
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF000000),
    text: Color(0xFFFFFFFF),
    textDim: Color(0xFFE0E0E0),
    accent: Color(0xFFFFE600),
    onAccent: Color(0xFF000000),
    secondary: Color(0xFFFFFFFF),
    thinking: Color(0xFF00E5FF),
    error: Color(0xFFFF6B6B),
    errorContainer: Color(0xFF5A0000),
    onErrorContainer: Color(0xFFFFFFFF),
    userBubble: Color(0xFFFFFFFF),
    onUserBubble: Color(0xFF000000),
    assistantBubble: Color(0xFF1C1C1C),
    outline: Color(0xFFFFFFFF),
  );

  static const all = [midnight, aurora, sunrise, paper, contrast];

  static List<String> get ids => [for (final s in all) s.id];

  /// The skin with this id; the default for anything unknown or missing.
  static VoiceSkin byId(Object? id) =>
      all.firstWhere((s) => s.id == id, orElse: () => midnight);

  /// What the Flutter widgets read through `Theme.of(context).colorScheme`.
  ColorScheme get scheme => ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: onAccent,
    secondary: secondary,
    onSecondary: onAccent,
    tertiary: thinking,
    onTertiary: onAccent,
    error: error,
    onError: onAccent,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: textDim,
    outline: outline,
    outlineVariant: outline,
    primaryContainer: userBubble,
    onPrimaryContainer: onUserBubble,
    surfaceContainerHighest: assistantBubble,
  );

  ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
  );

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// The palette for the native card (all `#RRGGBB`).
  Map<String, String> toSnapshot() => {
    'id': id,
    'surface': _hex(surface),
    'text': _hex(text),
    'text_dim': _hex(textDim),
    'accent': _hex(accent),
    'on_accent': _hex(onAccent),
    'thinking': _hex(thinking),
    'error': _hex(error),
    'user_bubble': _hex(userBubble),
    'on_user_bubble': _hex(onUserBubble),
    'outline': _hex(outline),
    'assistant_bubble': _hex(assistantBubble),
  };
}
