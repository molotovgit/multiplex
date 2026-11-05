import '../theme_spec.dart';
import '../theme_style.dart';

/// Dark open-source schemes, with the colours their authors published (read from the alacritty-theme
/// collection, Apache-2.0); each keeps its own licence, named in the credit.
abstract final class DarkThemes {
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
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.raised,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.floating,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 8, showTabs: true),
      backdrop: BackdropStyle(dim: 0.4, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.stars, BackdropPattern.mesh],
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
    style: ThemeStyle(
      shape: CornerShape.round,
      surface: SurfaceStyle.raised,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.45, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 6, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.mesh, BackdropPattern.dots, BackdropPattern.topo],
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
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.flat,
      density: StyleDensity.compact,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 4, showTabs: false),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 2, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.facets, BackdropPattern.scanlines],
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
    style: ThemeStyle(
      shape: CornerShape.rounded,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.rail,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.topo, BackdropPattern.mesh],
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
    style: ThemeStyle(
      shape: CornerShape.rounded,
      surface: SurfaceStyle.raised,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.1,
      nav: NavStyle.labelled,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.45, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 4, labelFont: KeyLabelFont.terminal),
    ),
    backdrops: [BackdropPattern.topo, BackdropPattern.facets],
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
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.normal,
      appFont: 'plex',
      textScale: 1.0,
      nav: NavStyle.iconsOnly,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 6, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.topo, BackdropPattern.dots],
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
    style: ThemeStyle(
      shape: CornerShape.rounded,
      surface: SurfaceStyle.glass,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.floating,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.4, blur: 4),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.mesh, BackdropPattern.stars],
  );

  static const dracula = ThemeSpec(
    id: 'dracula',
    name: 'Dracula',
    builtIn: true,
    credit: 'Dracula by Zeno Rocha (MIT)',
    ansi: [
      0xFF000000, 0xFFFF5555, 0xFF50FA7B, 0xFFF1FA8C, 0xFFBD93F9, 0xFFFF79C6, 0xFF8BE9FD, 0xFFBBBBBB, //
      0xFF555555, 0xFFFF5555, 0xFF50FA7B, 0xFFF1FA8C, 0xFFCAA9FA, 0xFFFF79C6, 0xFF8BE9FD, 0xFFFFFFFF,
    ],
    foreground: 0xFFF8F8F2,
    background: 0xFF282A36,
    cursor: 0xFFF8F8F2,
    accent: 0xFFBD93F9,
    style: ThemeStyle(
      shape: CornerShape.rounded,
      surface: SurfaceStyle.raised,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.rail,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 4, showTabs: true),
      backdrop: BackdropStyle(dim: 0.4, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.stars, BackdropPattern.facets],
  );

  static const solarizedDark = ThemeSpec(
    id: 'solarized-dark',
    name: 'Solarized Dark',
    builtIn: true,
    credit: 'Solarized by Ethan Schoonover (MIT)',
    ansi: [
      0xFF073642, 0xFFDC322F, 0xFF859900, 0xFFB58900, 0xFF268BD2, 0xFFD33682, 0xFF2AA198, 0xFFEEE8D5, //
      0xFF002B36, 0xFFCB4B16, 0xFF586E75, 0xFF657B83, 0xFF839496, 0xFF6C71C4, 0xFF93A1A1, 0xFFFDF6E3,
    ],
    foreground: 0xFF839496,
    background: 0xFF002B36,
    cursor: 0xFF839496,
    accent: 0xFF268BD2,
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.flat,
      density: StyleDensity.comfortable,
      appFont: 'plex',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 16, showTabs: false),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.dots, BackdropPattern.topo],
  );

  static const oneDark = ThemeSpec(
    id: 'one-dark',
    name: 'One Dark',
    builtIn: true,
    credit: 'One Dark from Atom (MIT)',
    ansi: [
      0xFF1E2127, 0xFFE06C75, 0xFF98C379, 0xFFD19A66, 0xFF61AFEF, 0xFFC678DD, 0xFF56B6C2, 0xFFABB2BF, //
      0xFF5C6370, 0xFFE06C75, 0xFF98C379, 0xFFD19A66, 0xFF61AFEF, 0xFFC678DD, 0xFF56B6C2, 0xFFFFFFFF,
    ],
    foreground: 0xFFABB2BF,
    background: 0xFF282C34,
    cursor: 0xFFABB2BF,
    accent: 0xFF61AFEF,
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.compact,
      appFont: 'jetbrains',
      textScale: 0.9,
      nav: NavStyle.iconsOnly,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 4, showTabs: true),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 2, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.scanlines, BackdropPattern.facets],
  );

  static const ayuDark = ThemeSpec(
    id: 'ayu-dark',
    name: 'Ayu Dark',
    builtIn: true,
    credit: 'Ayu by dempfi (MIT)',
    ansi: [
      0xFF01060E, 0xFFEA6C73, 0xFF91B362, 0xFFF9AF4F, 0xFF53BDFA, 0xFFFAE994, 0xFF90E1C6, 0xFFC7C7C7, //
      0xFF686868, 0xFFF07178, 0xFFC2D94C, 0xFFFFB454, 0xFF59C2FF, 0xFFFFEE99, 0xFF95E6CB, 0xFFFFFFFF,
    ],
    foreground: 0xFFB3B1AD,
    background: 0xFF0A0E14,
    cursor: 0xFFB3B1AD,
    accent: 0xFFFFB454,
    style: ThemeStyle(
      shape: CornerShape.round,
      surface: SurfaceStyle.flat,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.floating,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.45, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 6, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.mesh, BackdropPattern.dots],
  );

  static const nightOwl = ThemeSpec(
    id: 'night-owl',
    name: 'Night Owl',
    builtIn: true,
    credit: 'Night Owl by Sarah Drasner (MIT)',
    ansi: [
      0xFF011627, 0xFFEF5350, 0xFF22DA6E, 0xFFC5E478, 0xFF82AAFF, 0xFFC792EA, 0xFF21C7A8, 0xFFFFFFFF, //
      0xFF575656, 0xFFEF5350, 0xFF22DA6E, 0xFFFFEB95, 0xFF82AAFF, 0xFFC792EA, 0xFF7FDBCA, 0xFFFFFFFF,
    ],
    foreground: 0xFFD6DEEB,
    background: 0xFF011627,
    cursor: 0xFFD6DEEB,
    accent: 0xFF82AAFF,
    selection: 0xFF0D486E,
    style: ThemeStyle(
      shape: CornerShape.rounded,
      surface: SurfaceStyle.glass,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.35, blur: 2),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.stars, BackdropPattern.topo],
  );

  static const all = [tokyoNight, catppuccinMocha, gruvboxDark, nord, everforest, kanagawa, rosePine, dracula, solarizedDark, oneDark, ayuDark, nightOwl];
}
