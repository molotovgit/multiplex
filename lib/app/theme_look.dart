import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import 'terminal_fonts.dart';
import 'theme.dart';
import 'theme_spec.dart';
import 'theme_style.dart';

/// Corner radii for each kind of element, worked out from one
/// [CornerShape]. "Rounded" gives exactly the original look.
class StyleShapes {
  const StyleShapes({
    required this.card,
    required this.field,
    required this.button,
    required this.sheet,
    required this.dialog,
    required this.chip,
    required this.fab,
    required this.pill,
    required this.keyMax,
    required this.keyShare,
  });

  factory StyleShapes.of(CornerShape shape) => switch (shape) {
        CornerShape.square =>
          const StyleShapes(card: 0, field: 0, button: 0, sheet: 0, dialog: 0, chip: 0, fab: 0, pill: 0, keyMax: 0, keyShare: 0),
        CornerShape.soft =>
          const StyleShapes(card: 6, field: 6, button: 6, sheet: 12, dialog: 8, chip: 6, fab: 8, pill: 12, keyMax: 5, keyShare: 0.12),
        CornerShape.rounded => const StyleShapes(
            card: 14, field: 10, button: stadium, sheet: 28, dialog: 28, chip: 8, fab: 16, pill: 28, keyMax: 10, keyShare: 0.24),
        CornerShape.round => const StyleShapes(
            card: 24, field: 20, button: stadium, sheet: 32, dialog: 32, chip: stadium, fab: 28, pill: stadium, keyMax: 18, keyShare: 0.42),
      };

  /// A radius so large the ends become half circles.
  static const stadium = 999.0;

  final double card, field, button, sheet, dialog, chip, fab;

  /// The floating navigation bar.
  final double pill;

  /// Keyboard keys: a share of the key's visible height, up to [keyMax].
  final double keyMax;
  final double keyShare;

  double key(double visibleKeyHeight) => math.min(keyMax, visibleKeyHeight * keyShare);

  RoundedRectangleBorder border(double radius, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);
}

/// How surfaces (cards, bars, sheets) are painted for a [SurfaceStyle].
class SurfaceLook {
  const SurfaceLook({
    required this.style,
    required this.card,
    required this.bar,
    required this.side,
    required this.elevation,
    required this.shadow,
  });

  factory SurfaceLook.of(SurfaceStyle style, AppColors c) {
    // Shadows take the theme's own darkest tone, never plain black.
    final shadow = c.isDark
        ? Color.lerp(c.background, Colors.black, 0.6)!.withValues(alpha: 0.9)
        : Color.lerp(c.text, c.accent, 0.3)!.withValues(alpha: 0.28);
    return switch (style) {
      SurfaceStyle.flat => SurfaceLook(style: style, card: c.surface, bar: c.surface, side: BorderSide.none, elevation: 0, shadow: shadow),
      SurfaceStyle.outlined =>
        SurfaceLook(style: style, card: c.surface, bar: c.surface, side: BorderSide(color: c.outline), elevation: 0, shadow: shadow),
      SurfaceStyle.raised => SurfaceLook(style: style, card: c.surface, bar: c.surface, side: BorderSide.none, elevation: 3, shadow: shadow),
      SurfaceStyle.glass => SurfaceLook(
          style: style,
          card: c.surface.withValues(alpha: 0.62),
          bar: c.surface.withValues(alpha: 0.72),
          side: BorderSide(color: c.text.withValues(alpha: 0.12)),
          elevation: 0,
          shadow: shadow,
        ),
    };
  }

  final SurfaceStyle style;

  /// Cards and sheets.
  final Color card;

  /// Navigation bars.
  final Color bar;
  final BorderSide side;
  final double elevation;
  final Color shadow;

  bool get isGlass => style == SurfaceStyle.glass;

  /// Blur behind see-through bars.
  static const glassBlur = 18.0;
}

/// Finds the font family for the app font chosen in a style.
abstract final class AppFonts {
  /// Null means the platform's own font. A font the user added on another
  /// device is not here, so Flutter quietly uses the platform font.
  static String? family(String id) {
    if (id == ThemeStyle.systemFont) return null;
    for (final font in TerminalFonts.bundled) {
      if (font.id == id && font != TerminalFonts.system) return font.family;
    }
    return CustomFont(id: id, name: '', fileName: '').family;
  }

  /// The fonts offered for the app's text: the platform font, the bundled
  /// fonts and the user's own.
  static List<TerminalFont> choices(AppSettings settings) => [
        const TerminalFont(id: ThemeStyle.systemFont, name: 'System', family: null),
        for (final font in TerminalFonts.available(settings))
          if (font != TerminalFonts.system) font,
      ];
}

/// The parts of a theme's style that Material has no slot for: surfaces,
/// navigation, icons, terminal and keyboard. Read it with
/// `AppStyleTheme.of(context)`.
class AppStyleTheme extends ThemeExtension<AppStyleTheme> {
  AppStyleTheme(this.style, AppColors colors)
      : shapes = StyleShapes.of(style.shape),
        surfaces = SurfaceLook.of(style.surface, colors);

  final ThemeStyle style;
  final StyleShapes shapes;
  final SurfaceLook surfaces;

  static AppStyleTheme of(BuildContext context) =>
      Theme.of(context).extension<AppStyleTheme>() ?? AppStyleTheme(const ThemeStyle(), AppColors.derive(BuiltInThemes.matteBlack));

  @override
  AppStyleTheme copyWith() => this;

  @override
  AppStyleTheme lerp(AppStyleTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}
