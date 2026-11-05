import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../src/rust/api/terminal_types.dart';

/// The colours of the app shell (not the terminal). Two sets: dark is the
/// default because most SSH work happens in dark terminals; light follows
/// the system when the user picks it.
///
/// The accent is a warm amber, the colour of old phosphor terminals, and
/// it is used only where the user can act or where something is live.
class AppColors {
  const AppColors({
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

  final Color background;
  final Color surface;
  final Color raised;
  final Color outline;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;

  /// "Connected" / "running" green.
  final Color live;
  final Color danger;

  static const dark = AppColors(
    background: Color(0xFF121417),
    surface: Color(0xFF1A1D21),
    raised: Color(0xFF23272C),
    outline: Color(0xFF30353B),
    text: Color(0xFFE9E5DB),
    muted: Color(0xFF9BA1A8),
    accent: Color(0xFFF2B33D),
    onAccent: Color(0xFF231A06),
    live: Color(0xFF8FBF6A),
    danger: Color(0xFFE5716B),
  );

  static const light = AppColors(
    background: Color(0xFFF4F2ED),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFECE9E2),
    outline: Color(0xFFD8D3C8),
    text: Color(0xFF1C1E21),
    muted: Color(0xFF62676E),
    accent: Color(0xFFA9670F),
    onAccent: Color(0xFFFFFFFF),
    live: Color(0xFF3E7D2B),
    danger: Color(0xFFB8322C),
  );
}

/// Builds the Material themes from [AppColors]. Widgets stay standard
/// Material (they feel native on each platform); only colours, shapes and
/// the monospace font for addresses are ours.
abstract final class AppTheme {
  /// Monospace font for terminal text, host addresses and fingerprints.
  static const mono = 'JetBrainsMono';

  static ThemeData build(Brightness brightness) {
    final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.live,
      onSecondary: c.background,
      error: c.danger,
      onError: c.surface,
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
        indicatorColor: c.accent.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.accent : c.muted),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? c.text : c.muted,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.muted),
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
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.accent)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: c.raised, contentTextStyle: TextStyle(color: c.text)),
    );
  }
}

/// Gives widgets access to [AppColors] through the theme:
/// `AppColorsTheme.of(context).live`.
class AppColorsTheme extends ThemeExtension<AppColorsTheme> {
  const AppColorsTheme(this.colors);

  final AppColors colors;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColorsTheme>()?.colors ?? AppColors.dark;

  @override
  AppColorsTheme copyWith({AppColors? colors}) => AppColorsTheme(colors ?? this.colors);

  @override
  AppColorsTheme lerp(AppColorsTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// A named colour set for the terminal.
class TerminalTheme {
  const TerminalTheme({required this.id, required this.name, required this.ansi, required this.foreground, required this.background, required this.cursor});

  final String id;
  final String name;
  final List<int> ansi;
  final int foreground;
  final int background;
  final int cursor;

  TerminalPalette palette({required bool boldIsBright}) => TerminalPalette(
        ansi: Uint32List.fromList(ansi),
        foreground: foreground,
        background: background,
        cursor: cursor,
        boldIsBright: boldIsBright,
      );
}

/// The built-in terminal themes. All are VaultTerm's own colour sets.
abstract final class TerminalThemes {
  static const ember = TerminalTheme(
    id: 'ember',
    name: 'Ember',
    ansi: [
      0xFF1B1D1E, 0xFFE0605A, 0xFF8FBF6A, 0xFFE2B65C, 0xFF6B9BD8, 0xFFB78AD6, 0xFF5FB8B2, 0xFFD4D0C8, //
      0xFF5C6166, 0xFFF07F78, 0xFFA9D88A, 0xFFF3CD7E, 0xFF8DB6EA, 0xFFCDA8E6, 0xFF82D2CC, 0xFFF4F1EA,
    ],
    foreground: 0xFFE6E1D6,
    background: 0xFF141618,
    cursor: 0xFFF2B33D,
  );

  static const slate = TerminalTheme(
    id: 'slate',
    name: 'Slate',
    ansi: [
      0xFF1C2329, 0xFFE06C75, 0xFF7FC08A, 0xFFD9B96B, 0xFF6AA4E0, 0xFFB79BE3, 0xFF5CC4C9, 0xFFC9D1D9, //
      0xFF4F5B66, 0xFFF08A92, 0xFF9AD9A4, 0xFFEACF86, 0xFF8DBCF0, 0xFFCEB6F0, 0xFF7ED8DC, 0xFFEEF2F5,
    ],
    foreground: 0xFFD3DAE1,
    background: 0xFF111820,
    cursor: 0xFF7ED8DC,
  );

  static const paper = TerminalTheme(
    id: 'paper',
    name: 'Paper',
    ansi: [
      0xFF2B2B2B, 0xFFB3261E, 0xFF3C7A2A, 0xFF8A6200, 0xFF2556A8, 0xFF7B3FA0, 0xFF1C7A78, 0xFFBDB8AE, //
      0xFF6B6B6B, 0xFFD0453C, 0xFF4F9A3A, 0xFFA87A10, 0xFF3A6FC8, 0xFF9658BF, 0xFF2A9693, 0xFFE8E4DA,
    ],
    foreground: 0xFF24262A,
    background: 0xFFF6F3EC,
    cursor: 0xFFA9670F,
  );

  static const contrast = TerminalTheme(
    id: 'contrast',
    name: 'High contrast',
    ansi: [
      0xFF000000, 0xFFFF5555, 0xFF55FF55, 0xFFFFFF55, 0xFF5599FF, 0xFFFF55FF, 0xFF55FFFF, 0xFFE5E5E5, //
      0xFF7F7F7F, 0xFFFF8080, 0xFF80FF80, 0xFFFFFF80, 0xFF80B3FF, 0xFFFF80FF, 0xFF80FFFF, 0xFFFFFFFF,
    ],
    foreground: 0xFFFFFFFF,
    background: 0xFF000000,
    cursor: 0xFFFFD000,
  );

  static const all = [ember, slate, paper, contrast];

  static TerminalTheme byId(String id) => all.firstWhere((t) => t.id == id, orElse: () => ember);
}
