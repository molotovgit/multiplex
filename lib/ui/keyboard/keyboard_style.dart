import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'key_spec.dart';
import 'keyboard_settings.dart';

/// The keyboard's colours. Every one comes from the active theme's
/// [AppColors], so the keyboard restyles with each theme.
class KeyboardPalette {
  const KeyboardPalette({
    required this.panel,
    required this.key,
    required this.specialKey,
    required this.pressed,
    required this.label,
    required this.hint,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.bubble,
    required this.bubbleBorder,
    required this.shadow,
  });

  factory KeyboardPalette.from(AppColors c) => KeyboardPalette(
        panel: c.surface,
        key: c.raised,
        specialKey: Color.lerp(c.raised, c.outline, 0.7)!,
        pressed: Color.lerp(c.outline, c.text, 0.18)!,
        label: c.text,
        hint: c.muted,
        accent: c.accent,
        onAccent: c.onAccent,
        accentSoft: c.accent.withValues(alpha: 0.22),
        bubble: c.raised,
        bubbleBorder: c.outline,
        // Shadows use the theme's own darkest tone, never plain black.
        shadow: (c.isDark ? c.background : c.outline).withValues(alpha: 0.7),
      );

  static KeyboardPalette of(BuildContext context) => KeyboardPalette.from(AppColorsTheme.of(context));

  /// Behind the keys.
  final Color panel;
  final Color key;

  /// Modifiers, Enter, Backspace, page keys.
  final Color specialKey;
  final Color pressed;
  final Color label;

  /// The small alternate in the corner of a key.
  final Color hint;

  /// Locked modifiers and the chosen alternate.
  final Color accent;
  final Color onAccent;

  /// One-shot modifiers.
  final Color accentSoft;

  /// Preview bubble and alternates popup.
  final Color bubble;
  final Color bubbleBorder;
  final Color shadow;

  Color fill(KeySpec spec) => spec.tone == KeyTone.special ? specialKey : key;
}

/// Sizes of the keyboard for the screen it is on.
class KeyboardMetrics {
  const KeyboardMetrics({required this.rowHeight, required this.radius, required this.maxWidth, required this.compactWidth});

  /// The full row, gaps included: the touch target of each key.
  final double rowHeight;
  final double radius;

  /// On tablets and desktops the keys stop growing at this width and
  /// the keyboard is centred.
  final double maxWidth;

  /// True on narrow phones: labels of wide special keys switch to icons.
  final bool compactWidth;

  /// Space between keys, inside each key's touch target.
  static const gapX = 3.0;
  static const gapY = 4.0;

  /// The terminal row plus five rows of keys.
  static const rows = 6;

  /// Width of each key in the scrolling terminal row.
  static const topKeyWidth = 48.0;
  static const topKeyWideWidth = 60.0;

  static const _heights = {KeyHeightOption.compact: 44.0, KeyHeightOption.normal: 50.0, KeyHeightOption.large: 58.0};

  /// Phones in landscape give the keyboard at most this share of the
  /// screen height, so the terminal stays usable.
  static const landscapeShare = 0.55;

  /// Keys never get shorter than this, even in landscape.
  static const minRowHeight = 34.0;

  factory KeyboardMetrics.resolve(KeyboardSettings settings, Size screen) {
    var row = _heights[settings.keyHeight]!;
    final landscape = screen.width > screen.height;
    if (landscape) {
      row = math.max(minRowHeight, math.min(row, screen.height * landscapeShare / rows));
    }
    final visibleKey = row - gapY * 2;
    final radius = settings.shape == KeyShape.rounded ? math.min(10.0, visibleKey * 0.24) : 2.0;
    return KeyboardMetrics(rowHeight: row, radius: radius, maxWidth: landscape ? 840 : 600, compactWidth: screen.width < 400);
  }

  double get height => rowHeight * rows;
}

/// Text styles of the keys, from the theme's text roles.
class KeyTextStyles {
  const KeyTextStyles({required this.character, required this.word, required this.hint});

  factory KeyTextStyles.of(BuildContext context, KeyboardSettings settings, KeyboardPalette palette) {
    final text = Theme.of(context).textTheme;
    final weight = settings.boldLabels ? FontWeight.w700 : FontWeight.w400;
    return KeyTextStyles(
      character: text.titleLarge?.copyWith(color: palette.label, fontWeight: weight, height: 1),
      word: text.labelLarge?.copyWith(color: palette.label, fontWeight: settings.boldLabels ? FontWeight.w700 : FontWeight.w500, height: 1),
      hint: text.labelSmall?.copyWith(color: palette.hint, fontWeight: weight, height: 1),
    );
  }

  /// Single characters.
  final TextStyle? character;

  /// Words such as Ctrl, Esc, F5.
  final TextStyle? word;
  final TextStyle? hint;
}
