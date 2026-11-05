import 'dart:typed_data';

import '../data/models.dart';
import '../src/rust/api/terminal_types.dart';

/// One theme for the whole app: the terminal colours plus an accent. The
/// app's own surfaces are derived from these (see [AppColors.derive]), so
/// switching a theme restyles everything at once, terminal and screens
/// alike.
class ThemeSpec {
  const ThemeSpec({
    required this.id,
    required this.name,
    required this.ansi,
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.accent,
    this.selection,
    this.credit,
    this.builtIn = false,
  });

  final String id;
  final String name;

  /// 16 colours, 0xAARRGGBB: 8 normal then 8 bright.
  final List<int> ansi;
  final int foreground;
  final int background;
  final int cursor;

  /// The one colour used for buttons, selection and highlights.
  final int accent;
  final int? selection;

  /// Where the colours come from, shown in the theme gallery.
  final String? credit;
  final bool builtIn;

  /// True when the background is dark.
  bool get isDark {
    final r = (background >> 16) & 0xFF, g = (background >> 8) & 0xFF, b = background & 0xFF;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 128;
  }

  TerminalPalette palette({required bool boldIsBright}) => TerminalPalette(
        ansi: Uint32List.fromList(ansi),
        foreground: foreground,
        background: background,
        cursor: cursor,
        boldIsBright: boldIsBright,
      );

  ThemeSpec copyWith({String? id, String? name, List<int>? ansi, int? foreground, int? background, int? cursor, int? accent, int? Function()? selection}) =>
      ThemeSpec(
        id: id ?? this.id,
        name: name ?? this.name,
        ansi: ansi ?? this.ansi,
        foreground: foreground ?? this.foreground,
        background: background ?? this.background,
        cursor: cursor ?? this.cursor,
        accent: accent ?? this.accent,
        selection: selection != null ? selection() : this.selection,
        credit: credit,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ansi': ansi,
        'foreground': foreground,
        'background': background,
        'cursor': cursor,
        'accent': accent,
        'selection': selection,
      };

  factory ThemeSpec.fromJson(Map<String, dynamic> j) {
    final ansi = (j['ansi'] is List ? (j['ansi'] as List).whereType<num>().map((e) => e.toInt()).toList() : <int>[]);
    final fg = Json.integer(j, 'foreground', 0xFFE6E1D6);
    return ThemeSpec(
      id: Json.str(j, 'id'),
      name: Json.str(j, 'name', 'Custom theme'),
      ansi: List.generate(16, (i) => i < ansi.length ? ansi[i] : (i >= 8 && i - 8 < ansi.length ? ansi[i - 8] : fg)),
      foreground: fg,
      background: Json.integer(j, 'background', 0xFF141618),
      cursor: Json.integer(j, 'cursor', fg),
      accent: Json.integer(j, 'accent', 0xFFF2B33D),
      selection: j['selection'] is num ? (j['selection'] as num).toInt() : null,
    );
  }
}

/// The themes that come with VaultTerm.
///
/// Ember, Slate, Paper and High contrast are VaultTerm's own. The others
/// use the published colours of popular open-source schemes, read from
/// the alacritty-theme collection (Apache-2.0) with VaultTerm's own theme
/// importer; each scheme keeps its own licence, named in [ThemeSpec.credit].
abstract final class BuiltInThemes {
  static const ember = ThemeSpec(
    id: 'ember',
    name: 'Ember',
    builtIn: true,
    credit: 'VaultTerm',
    ansi: [
      0xFF1B1D1E, 0xFFE0605A, 0xFF8FBF6A, 0xFFE2B65C, 0xFF6B9BD8, 0xFFB78AD6, 0xFF5FB8B2, 0xFFD4D0C8, //
      0xFF5C6166, 0xFFF07F78, 0xFFA9D88A, 0xFFF3CD7E, 0xFF8DB6EA, 0xFFCDA8E6, 0xFF82D2CC, 0xFFF4F1EA,
    ],
    foreground: 0xFFE6E1D6,
    background: 0xFF141618,
    cursor: 0xFFF2B33D,
    accent: 0xFFF2B33D,
  );

  static const slate = ThemeSpec(
    id: 'slate',
    name: 'Slate',
    builtIn: true,
    credit: 'VaultTerm',
    ansi: [
      0xFF1C2329, 0xFFE06C75, 0xFF7FC08A, 0xFFD9B96B, 0xFF6AA4E0, 0xFFB79BE3, 0xFF5CC4C9, 0xFFC9D1D9, //
      0xFF4F5B66, 0xFFF08A92, 0xFF9AD9A4, 0xFFEACF86, 0xFF8DBCF0, 0xFFCEB6F0, 0xFF7ED8DC, 0xFFEEF2F5,
    ],
    foreground: 0xFFD3DAE1,
    background: 0xFF111820,
    cursor: 0xFF7ED8DC,
    accent: 0xFF7ED8DC,
  );

  static const paper = ThemeSpec(
    id: 'paper',
    name: 'Paper',
    builtIn: true,
    credit: 'VaultTerm',
    ansi: [
      0xFF2B2B2B, 0xFFB3261E, 0xFF3C7A2A, 0xFF8A6200, 0xFF2556A8, 0xFF7B3FA0, 0xFF1C7A78, 0xFFBDB8AE, //
      0xFF6B6B6B, 0xFFD0453C, 0xFF4F9A3A, 0xFFA87A10, 0xFF3A6FC8, 0xFF9658BF, 0xFF2A9693, 0xFFE8E4DA,
    ],
    foreground: 0xFF24262A,
    background: 0xFFF6F3EC,
    cursor: 0xFFA9670F,
    accent: 0xFFA9670F,
  );

  static const contrast = ThemeSpec(
    id: 'contrast',
    name: 'High contrast',
    builtIn: true,
    credit: 'VaultTerm',
    ansi: [
      0xFF000000, 0xFFFF5555, 0xFF55FF55, 0xFFFFFF55, 0xFF5599FF, 0xFFFF55FF, 0xFF55FFFF, 0xFFE5E5E5, //
      0xFF7F7F7F, 0xFFFF8080, 0xFF80FF80, 0xFFFFFF80, 0xFF80B3FF, 0xFFFF80FF, 0xFF80FFFF, 0xFFFFFFFF,
    ],
    foreground: 0xFFFFFFFF,
    background: 0xFF000000,
    cursor: 0xFFFFD000,
    accent: 0xFFFFD000,
  );

  static const tokyoNight = ThemeSpec(
    id: 'tokyo-night',
    name: 'Tokyo Night',
    builtIn: true,
    credit: 'Tokyo Night by enkia (MIT)',
    ansi: [
      0xFF32344A, 0xFFF7768E, 0xFF9ECE6A, 0xFFE0AF68, 0xFF7AA2F7, 0xFFAD8EE6, 0xFF449DAB, 0xFF787C99, //
      0xFF444B6A, 0xFFFF7A93, 0xFFB9F27C, 0xFFFF9E64, 0xFF7DA6FF, 0xFFBB9AF7, 0xFF0DB9D7, 0xFFACB0D0,
    ],
    foreground: 0xFFA9B1D6,
    background: 0xFF1A1B26,
    cursor: 0xFFC0CAF5,
    accent: 0xFF7AA2F7,
  );

  static const catppuccinMocha = ThemeSpec(
    id: 'catppuccin-mocha',
    name: 'Catppuccin Mocha',
    builtIn: true,
    credit: 'Catppuccin (MIT)',
    ansi: [
      0xFF45475A, 0xFFF38BA8, 0xFFA6E3A1, 0xFFF9E2AF, 0xFF89B4FA, 0xFFF5C2E7, 0xFF94E2D5, 0xFFBAC2DE, //
      0xFF585B70, 0xFFF38BA8, 0xFFA6E3A1, 0xFFF9E2AF, 0xFF89B4FA, 0xFFF5C2E7, 0xFF94E2D5, 0xFFA6ADC8,
    ],
    foreground: 0xFFCDD6F4,
    background: 0xFF1E1E2E,
    cursor: 0xFFF5E0DC,
    accent: 0xFFCBA6F7,
  );

  static const catppuccinLatte = ThemeSpec(
    id: 'catppuccin-latte',
    name: 'Catppuccin Latte',
    builtIn: true,
    credit: 'Catppuccin (MIT)',
    ansi: [
      0xFF5C5F77, 0xFFD20F39, 0xFF40A02B, 0xFFDF8E1D, 0xFF1E66F5, 0xFFEA76CB, 0xFF179299, 0xFFACB0BE, //
      0xFF6C6F85, 0xFFD20F39, 0xFF40A02B, 0xFFDF8E1D, 0xFF1E66F5, 0xFFEA76CB, 0xFF179299, 0xFFBCC0CC,
    ],
    foreground: 0xFF4C4F69,
    background: 0xFFEFF1F5,
    cursor: 0xFFDC8A78,
    accent: 0xFF8839EF,
  );

  static const gruvboxDark = ThemeSpec(
    id: 'gruvbox-dark',
    name: 'Gruvbox Dark',
    builtIn: true,
    credit: 'Gruvbox by morhetz (MIT)',
    ansi: [
      0xFF282828, 0xFFCC241D, 0xFF98971A, 0xFFD79921, 0xFF458588, 0xFFB16286, 0xFF689D6A, 0xFFA89984, //
      0xFF928374, 0xFFFB4934, 0xFFB8BB26, 0xFFFABD2F, 0xFF83A598, 0xFFD3869B, 0xFF8EC07C, 0xFFEBDBB2,
    ],
    foreground: 0xFFEBDBB2,
    background: 0xFF282828,
    cursor: 0xFFEBDBB2,
    accent: 0xFFFABD2F,
  );

  static const nord = ThemeSpec(
    id: 'nord',
    name: 'Nord',
    builtIn: true,
    credit: 'Nord by Arctic Ice Studio (MIT)',
    ansi: [
      0xFF3B4252, 0xFFBF616A, 0xFFA3BE8C, 0xFFEBCB8B, 0xFF81A1C1, 0xFFB48EAD, 0xFF88C0D0, 0xFFE5E9F0, //
      0xFF4C566A, 0xFFBF616A, 0xFFA3BE8C, 0xFFEBCB8B, 0xFF81A1C1, 0xFFB48EAD, 0xFF8FBCBB, 0xFFECEFF4,
    ],
    foreground: 0xFFD8DEE9,
    background: 0xFF2E3440,
    cursor: 0xFFD8DEE9,
    accent: 0xFF88C0D0,
  );

  static const everforest = ThemeSpec(
    id: 'everforest-dark',
    name: 'Everforest',
    builtIn: true,
    credit: 'Everforest by sainnhe (MIT)',
    ansi: [
      0xFF475258, 0xFFE67E80, 0xFFA7C080, 0xFFDBBC7F, 0xFF7FBBB3, 0xFFD699B6, 0xFF83C092, 0xFFD3C6AA, //
      0xFF475258, 0xFFE67E80, 0xFFA7C080, 0xFFDBBC7F, 0xFF7FBBB3, 0xFFD699B6, 0xFF83C092, 0xFFD3C6AA,
    ],
    foreground: 0xFFD3C6AA,
    background: 0xFF2D353B,
    cursor: 0xFFD3C6AA,
    accent: 0xFFA7C080,
  );

  static const kanagawa = ThemeSpec(
    id: 'kanagawa-wave',
    name: 'Kanagawa',
    builtIn: true,
    credit: 'Kanagawa by rebelot (MIT)',
    ansi: [
      0xFF090618, 0xFFC34043, 0xFF76946A, 0xFFC0A36E, 0xFF7E9CD8, 0xFF957FB8, 0xFF6A9589, 0xFFC8C093, //
      0xFF727169, 0xFFE82424, 0xFF98BB6C, 0xFFE6C384, 0xFF7FB4CA, 0xFF938AA9, 0xFF7AA89F, 0xFFDCD7BA,
    ],
    foreground: 0xFFDCD7BA,
    background: 0xFF1F1F28,
    cursor: 0xFFDCD7BA,
    accent: 0xFF7E9CD8,
    selection: 0xFF2D4F67,
  );

  static const rosePine = ThemeSpec(
    id: 'rose-pine',
    name: 'Rosé Pine',
    builtIn: true,
    credit: 'Rosé Pine (MIT)',
    ansi: [
      0xFF26233A, 0xFFEB6F92, 0xFF31748F, 0xFFF6C177, 0xFF9CCFD8, 0xFFC4A7E7, 0xFFEBBCBA, 0xFFE0DEF4, //
      0xFF6E6A86, 0xFFEB6F92, 0xFF31748F, 0xFFF6C177, 0xFF9CCFD8, 0xFFC4A7E7, 0xFFEBBCBA, 0xFFE0DEF4,
    ],
    foreground: 0xFFE0DEF4,
    background: 0xFF191724,
    cursor: 0xFFE0DEF4,
    accent: 0xFFEBBCBA,
    selection: 0xFF403D52,
  );

  static const all = [
    ember,
    tokyoNight,
    catppuccinMocha,
    gruvboxDark,
    nord,
    everforest,
    kanagawa,
    rosePine,
    slate,
    contrast,
    paper,
    catppuccinLatte,
  ];

  static const defaultId = 'ember';
}
