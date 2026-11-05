import '../theme_spec.dart';
import '../theme_style.dart';

/// Light open-source schemes, with the colours their authors published (read from the alacritty-theme
/// collection, Apache-2.0); each keeps its own licence, named in the credit.
abstract final class LightThemes {
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
    style: ThemeStyle(
      shape: CornerShape.round,
      surface: SurfaceStyle.raised,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.1,
      nav: NavStyle.floating,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.45, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 6, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.mesh, BackdropPattern.facets],
  );

  static const solarizedLight = ThemeSpec(
    id: 'solarized-light',
    name: 'Solarized Light',
    builtIn: true,
    credit: 'Solarized by Ethan Schoonover (MIT)',
    ansi: [
      0xFF073642, 0xFFDC322F, 0xFF859900, 0xFFB58900, 0xFF268BD2, 0xFFD33682, 0xFF2AA198, 0xFFEEE8D5, //
      0xFF002B36, 0xFFCB4B16, 0xFF586E75, 0xFF657B83, 0xFF839496, 0xFF6C71C4, 0xFF93A1A1, 0xFFFDF6E3,
    ],
    foreground: 0xFF586E75,
    background: 0xFFFDF6E3,
    cursor: 0xFF586E75,
    accent: 0xFF268BD2,
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.normal,
      appFont: 'plex',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 16, showTabs: true),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.dots, BackdropPattern.mesh],
  );

  static const gruvboxLight = ThemeSpec(
    id: 'gruvbox-light',
    name: 'Gruvbox Light',
    builtIn: true,
    credit: 'Gruvbox by morhetz (MIT)',
    ansi: [
      0xFFFBF1C7, 0xFFCC241D, 0xFF98971A, 0xFFD79921, 0xFF458588, 0xFFB16286, 0xFF689D6A, 0xFF7C6F64, //
      0xFF928374, 0xFF9D0006, 0xFF79740E, 0xFFB57614, 0xFF076678, 0xFF8F3F71, 0xFF427B58, 0xFF3C3836,
    ],
    foreground: 0xFF3C3836,
    background: 0xFFFBF1C7,
    cursor: 0xFF3C3836,
    accent: 0xFF076678,
    style: ThemeStyle(
      shape: CornerShape.square,
      surface: SurfaceStyle.raised,
      density: StyleDensity.compact,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 4, showTabs: false),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 2, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.facets, BackdropPattern.dots],
  );

  static const ayuLight = ThemeSpec(
    id: 'ayu-light',
    name: 'Ayu Light',
    builtIn: true,
    credit: 'Ayu by dempfi (MIT)',
    ansi: [
      0xFF010101, 0xFFE7666A, 0xFF80AB24, 0xFFEBA54D, 0xFF4196DF, 0xFF9870C3, 0xFF51B891, 0xFFC1C1C1, //
      0xFF343434, 0xFFEE9295, 0xFF9FD32F, 0xFFF0BC7B, 0xFF6DAEE6, 0xFFB294D2, 0xFF75C7A8, 0xFFDBDBDB,
    ],
    foreground: 0xFF5C6166,
    background: 0xFFFCFCFC,
    cursor: 0xFF5C6166,
    accent: 0xFF4196DF,
    style: ThemeStyle(
      shape: CornerShape.round,
      surface: SurfaceStyle.flat,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.1,
      nav: NavStyle.floating,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 16, showTabs: false),
      backdrop: BackdropStyle(dim: 0.4, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 6, labelFont: KeyLabelFont.terminal),
    ),
    backdrops: [BackdropPattern.topo, BackdropPattern.scanlines],
  );

  static const all = [catppuccinLatte, solarizedLight, gruvboxLight, ayuLight];
}
