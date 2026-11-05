import 'package:flutter/material.dart';

import 'theme_spec.dart';

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
      text: fg,
      muted: mix(fg, bg, 0.42),
      accent: accent,
      onAccent: accent.computeLuminance() > 0.4 ? mix(bg, Colors.black, dark ? 0.4 : 0.85) : Colors.white,
      live: Color(theme.ansi[2]),
      danger: Color(theme.ansi[1]),
    );
  }
}

/// Builds the Material theme for a [ThemeSpec]. Controls stay standard
/// Material, so they behave the way the platform's users expect; only
/// colours and shapes come from the theme.
abstract final class AppTheme {
  static ThemeData build(ThemeSpec spec) {
    final c = AppColors.derive(spec);
    final brightness = c.isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.live,
      onSecondary: c.background,
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
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    final selectedOrMuted = WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.muted);
    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      extensions: [AppColorsTheme(c)],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(color: c.text, fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: selectedOrMuted.resolve(s))),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => base.textTheme.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? c.text : c.muted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.2),
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.muted),
        selectedLabelTextStyle: TextStyle(color: c.text, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: c.muted),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.outline)),
      ),
      listTileTheme: ListTileThemeData(iconColor: c.muted, textColor: c.text),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.raised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.accent, width: 1.5)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, showDragHandle: true),
      dialogTheme: DialogThemeData(backgroundColor: c.surface),
      popupMenuTheme: PopupMenuThemeData(color: c.raised),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.raised,
        contentTextStyle: TextStyle(color: c.text),
        actionTextColor: c.accent,
      ),
    );
  }
}

/// Gives widgets the current [AppColors]: `AppColorsTheme.of(context).live`.
class AppColorsTheme extends ThemeExtension<AppColorsTheme> {
  const AppColorsTheme(this.colors);

  final AppColors colors;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColorsTheme>()?.colors ?? AppColors.derive(BuiltInThemes.ember);

  @override
  AppColorsTheme copyWith({AppColors? colors}) => AppColorsTheme(colors ?? this.colors);

  @override
  AppColorsTheme lerp(AppColorsTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}
