import 'package:flutter/material.dart';

import 'gloss.dart';
import 'theme_look.dart';
import 'theme_spec.dart';
import 'theme_style.dart';

/// The colours of the app's own screens, worked out from the active
/// [ThemeSpec] so the whole app matches the terminal theme.
class AppColors {
  const AppColors({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.raised,
    required this.outline,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.live,
    required this.danger,
  });

  final bool isDark;
  final Color background;

  /// Cards, sheets, the navigation bar.
  final Color surface;

  /// Input fields and pressed states, one step above [surface].
  final Color raised;
  final Color outline;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;

  /// "Connected" / "running", taken from the theme's green.
  final Color live;

  /// Errors and destructive actions, taken from the theme's red.
  final Color danger;

  /// Surfaces are the background mixed a little towards the text colour
  /// (dark themes) or towards white (light themes).
  factory AppColors.derive(ThemeSpec theme) {
    final bg = Color(theme.background);
    final fg = Color(theme.foreground);
    final accent = Color(theme.accent);
    final dark = theme.isDark;
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    return AppColors(
      isDark: dark,
      background: bg,
      surface: dark ? mix(bg, fg, 0.05) : mix(bg, Colors.white, 0.6),
      raised: dark ? mix(bg, fg, 0.10) : mix(bg, fg, 0.06),
      outline: dark ? mix(bg, fg, 0.17) : mix(bg, fg, 0.15),
      // The app's text must read at 4.5:1 on cards even when a scheme's
      // own text colour is softer; the terminal keeps the exact colour.
      text: _Contrast.readable(fg, dark ? mix(bg, fg, 0.05) : mix(bg, Colors.white, 0.6)),
      muted: _Contrast.readableMuted(fg, bg, dark ? mix(bg, fg, 0.05) : mix(bg, Colors.white, 0.6)),
      accent: accent,
      onAccent: accent.computeLuminance() > 0.4 ? mix(bg, Colors.black, dark ? 0.4 : 0.85) : Colors.white,
      live: Color(theme.ansi[2]),
      danger: Color(theme.ansi[1]),
    );
  }
}

/// Contrast helpers for derived colours.
abstract final class _Contrast {
  /// WCAG minimum for normal text.
  static const minimum = 4.5;

  /// WCAG contrast ratio between two colours (1 to 21).
  static double ratio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The softest mix of text towards the background that still reads well
  /// on the surface colour: starts at 40 % and moves back towards the text
  /// colour until the contrast reaches 4.5:1.
  static Color readableMuted(Color text, Color background, Color surface) {
    for (var t = 0.40; t > 0; t -= 0.02) {
      final candidate = Color.lerp(text, background, t)!;
      if (ratio(candidate, surface) >= minimum) return candidate;
    }
    return readable(text, surface);
  }

  /// [color] as it is when it reads well on [surface]; otherwise moved
  /// towards white (dark surfaces) or black (light ones) until it does.
  static Color readable(Color color, Color surface) {
    if (ratio(color, surface) >= minimum) return color;
    final target = surface.computeLuminance() < 0.18 ? Colors.white : Colors.black;
    for (var t = 0.05; t < 1; t += 0.05) {
      final candidate = Color.lerp(color, target, t)!;
      if (ratio(candidate, surface) >= minimum) return candidate;
    }
    return target;
  }
}

/// Builds the Material theme for a [ThemeSpec]. Controls stay standard
/// Material, so they behave the way the platform's users expect; colours,
/// shapes, surfaces, density and font come from the theme and its style.
abstract final class AppTheme {
  /// Space and row height per density. Normal keeps Material's own.
  static VisualDensity? _density(StyleDensity d) => switch (d) {
        StyleDensity.compact => VisualDensity.compact,
        StyleDensity.normal => null,
        StyleDensity.comfortable => const VisualDensity(horizontal: 0, vertical: 1),
      };

  /// Bottom bar labels. Monospace app fonts are wider, so five labels of a
  /// phone-width bar would run into each other: drop the letter spacing and
  /// one point of size there.
  static TextStyle? _navLabel(TextStyle? base, {required bool monospace}) {
    if (base == null || !monospace) return base;
    return base.copyWith(letterSpacing: 0, fontSize: (base.fontSize ?? 12) - 1);
  }

  static double? _listPadding(StyleDensity d) => switch (d) {
        StyleDensity.compact => 4,
        StyleDensity.normal => null,
        StyleDensity.comfortable => 12,
      };

  /// The theme's text size on top of the phone's. Material only adds the
  /// sizes later, so they are filled in here first; at 100 % nothing
  /// changes.
  static TextTheme _scaled(TextTheme text, double scale) =>
      scale == 1.0 ? text : Typography.englishLike2021.merge(text).apply(fontSizeFactor: scale);

  static ThemeData build(ThemeSpec spec) {
    final c = AppColors.derive(spec);
    final style = spec.style;
    final look = AppStyleTheme(style, c);
    final shapes = look.shapes;
    final surfaces = look.surfaces;
    final brightness = c.isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      // Material paints selected segments, tonal buttons and chips with
      // the secondary colours. They follow the accent, so every theme has
      // one highlight colour; the green "live" colour is used directly
      // where something is connected or running.
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: Color.alphaBlend(c.accent.withValues(alpha: 0.22), c.surface),
      onSecondaryContainer: c.text,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      outline: c.outline,
      outlineVariant: c.outline,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.raised,
    );
    final material = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppFonts.family(style.appFont),
      visualDensity: _density(style.density),
    );
    // Two weights across the app: 400 for text, 600 for titles and the
    // labels on buttons, tabs and menus (Material would add a third, 500).
    final base = material.copyWith(
      textTheme: material.textTheme.copyWith(
        labelLarge: material.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: material.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: material.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelMedium: material.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    final scaled = base.copyWith(textTheme: _scaled(base.textTheme, style.textScale));
    final selectedOrMuted = WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.muted);
    final themed = scaled.copyWith(
      scaffoldBackgroundColor: c.background,
      extensions: [AppColorsTheme(c), look],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: scaled.textTheme.titleLarge?.copyWith(color: c.text, fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaces.bar,
        elevation: surfaces.elevation,
        shadowColor: surfaces.shadow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accent.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: selectedOrMuted.resolve(s))),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => _navLabel(scaled.textTheme.labelMedium, monospace: style.appFont != ThemeStyle.systemFont)?.copyWith(
            color: s.contains(WidgetState.selected) ? c.text : c.muted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaces.bar,
        indicatorColor: c.accent.withValues(alpha: 0.2),
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.muted),
        selectedLabelTextStyle: scaled.textTheme.labelMedium?.copyWith(color: c.text, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: scaled.textTheme.labelMedium?.copyWith(color: c.muted, fontWeight: FontWeight.w400),
      ),
      cardTheme: CardThemeData(
        color: surfaces.card,
        elevation: surfaces.elevation,
        shadowColor: surfaces.shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: shapes.border(shapes.card, surfaces.side),
      ),
      listTileTheme: ListTileThemeData(iconColor: c.muted, textColor: c.text, minVerticalPadding: _listPadding(style.density)),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.raised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(shapes.field), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(shapes.field), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(shapes.field), borderSide: BorderSide(color: c.accent, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(shapes.border(shapes.button)))),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(shapes.border(shapes.button)))),
      textButtonTheme: TextButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(shapes.border(shapes.button)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(shapes.border(shapes.button)))),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(shapes.border(shapes.button)))),
      chipTheme: ChipThemeData(shape: shapes.border(shapes.chip)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: shapes.border(shapes.fab),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.sheet))),
      ),
      dialogTheme: DialogThemeData(backgroundColor: c.surface, shape: shapes.border(shapes.dialog)),
      popupMenuTheme: PopupMenuThemeData(color: c.raised),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.raised,
        contentTextStyle: TextStyle(color: c.text),
        actionTextColor: c.accent,
      ),
    );
    return surfaces.isGlossy ? _glossy(themed, c, spec) : themed;
  }

  /// The glossy style: banded title bars and bottom bar in the accent with
  /// white text, shaded buttons with a dark edge, and a green main button
  /// with a rounded end.
  static ThemeData _glossy(ThemeData t, AppColors c, ThemeSpec theme) {
    final bar = Gloss.darken(c.accent, 0.1);
    final edge = Gloss.darken(c.accent, 0.55);
    final green = Color(theme.ansi[2]);
    final shine = [Shadow(offset: const Offset(1, 1), color: Gloss.darken(c.accent, 0.55))];
    final buttons = Gloss.buttonStyle(face: c.background, edge: edge, text: c.text);
    const white = Colors.white;
    return t.copyWith(
      appBarTheme: t.appBarTheme.copyWith(
        backgroundColor: c.accent,
        foregroundColor: white,
        iconTheme: const IconThemeData(color: white),
        actionsIconTheme: const IconThemeData(color: white),
        shape: GlossBorder(side: BorderSide(color: bar)),
        titleTextStyle: t.appBarTheme.titleTextStyle?.copyWith(color: white, fontWeight: FontWeight.w700, shadows: shine),
      ),
      navigationBarTheme: t.navigationBarTheme.copyWith(
        backgroundColor: c.accent,
        elevation: 0,
        indicatorColor: Gloss.darken(c.accent, 0.35),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? white : white.withValues(alpha: 0.85))),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t.navigationBarTheme.labelTextStyle?.resolve(s)?.copyWith(color: s.contains(WidgetState.selected) ? white : white.withValues(alpha: 0.85), shadows: shine),
        ),
      ),
      floatingActionButtonTheme: t.floatingActionButtonTheme.copyWith(
        backgroundColor: green,
        foregroundColor: white,
        elevation: 2,
        highlightElevation: 0,
        // A start button: square at the start, round at the end.
        shape: GlossBorder(radius: const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(28)), side: BorderSide(color: Gloss.darken(green, 0.35))),
        extendedTextStyle: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, shadows: [Shadow(offset: const Offset(1, 1), color: Gloss.darken(green, 0.5))]),
      ),
      filledButtonTheme: FilledButtonThemeData(style: buttons),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttons),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttons),
    );
  }
}

/// Gives widgets the current [AppColors]: `AppColorsTheme.of(context).live`.
class AppColorsTheme extends ThemeExtension<AppColorsTheme> {
  const AppColorsTheme(this.colors);

  final AppColors colors;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColorsTheme>()?.colors ?? AppColors.derive(BuiltInThemes.matteBlack);

  @override
  AppColorsTheme copyWith({AppColors? colors}) => AppColorsTheme(colors ?? this.colors);

  @override
  AppColorsTheme lerp(AppColorsTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}
