import '../theme_spec.dart';
import '../theme_style.dart';

/// Multiplex's own looks (shapes, bars, keyboards, backdrops), each on a
/// real, credited colour scheme read from its published file.
abstract final class OriginalThemes {
  static const matteBlack = ThemeSpec(
    id: 'matte-black',
    name: 'Matte Black',
    builtIn: true,
    credit: 'Matte Black from Omarchy (MIT)',
    ansi: [
      0xFF121212, 0xFFD35F5F, 0xFFFFC107, 0xFFB91C1C, 0xFFE68E0D, 0xFFD35F5F, 0xFFBEBEBE, 0xFFBEBEBE, //
      0xFF333333, 0xFFB91C1C, 0xFFFFC107, 0xFFB90A0A, 0xFFF59E0B, 0xFFB91C1C, 0xFFEAEAEA, 0xFFBEBEBE,
    ],
    foreground: 0xFFBEBEBE,
    background: 0xFF121212,
    cursor: 0xFFBEBEBE,
    accent: 0xFFE68E0D,
    selection: 0xFF2A2A2A,
    style: ThemeStyle(
      shape: CornerShape.rounded,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 4, showTabs: false),
      backdrop: BackdropStyle(dim: 0.4, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.dots, BackdropPattern.mesh],
    // Starts on the plain colour, the look Multiplex always had.
    activeBackground: 2,
  );

  static const iceberg = ThemeSpec(
    id: 'iceberg',
    name: 'Iceberg',
    builtIn: true,
    credit: 'Iceberg by cocopon (MIT)',
    ansi: [
      0xFF1E2132, 0xFFE27878, 0xFFB4BE82, 0xFFE2A478, 0xFF84A0C6, 0xFFA093C7, 0xFF89B8C2, 0xFFC6C8D1, //
      0xFF6B7089, 0xFFE98989, 0xFFC0CA8E, 0xFFE9B189, 0xFF91ACD1, 0xFFADA0D3, 0xFF95C4CE, 0xFFD2D4DE,
    ],
    foreground: 0xFFC6C8D1,
    background: 0xFF161821,
    cursor: 0xFFC6C8D1,
    accent: 0xFF84A0C6,
    selection: 0xFF272C42,
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.raised,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 8, showTabs: true),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.topo, BackdropPattern.facets],
  );

  static const oxocarbon = ThemeSpec(
    id: 'oxocarbon',
    name: 'Oxocarbon',
    builtIn: true,
    credit: 'Oxocarbon by nyoom-engineering, IBM Carbon colours (MIT)',
    ansi: [
      0xFF161616, 0xFFEE5396, 0xFF42BE65, 0xFFFF7EB6, 0xFF33B1FF, 0xFFBE95FF, 0xFF3DDBD9, 0xFFFFFFFF, //
      0xFF525252, 0xFFEE5396, 0xFF42BE65, 0xFFFF7EB6, 0xFF33B1FF, 0xFFBE95FF, 0xFF3DDBD9, 0xFFFFFFFF,
    ],
    foreground: 0xFFFFFFFF,
    background: 0xFF1B1B1B,
    cursor: 0xFF78A9FF,
    accent: 0xFF33B1FF,
    style: ThemeStyle(
      shape: CornerShape.square,
      surface: SurfaceStyle.flat,
      density: StyleDensity.compact,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.iconsOnly,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 0, showTabs: false),
      backdrop: BackdropStyle(dim: 0.6, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 2, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.scanlines, BackdropPattern.dots],
  );

  static const hackerman = ThemeSpec(
    id: 'hackerman',
    name: 'Hackerman',
    builtIn: true,
    credit: 'Hackerman from Omarchy (MIT)',
    ansi: [
      0xFF0B0C16, 0xFF50F872, 0xFF4FE88F, 0xFF50F7D4, 0xFF829DD4, 0xFF86A7DF, 0xFF7CF8F7, 0xFFDDF7FF, //
      0xFF2D3450, 0xFF85FF9D, 0xFF9CF7C2, 0xFFA4FFEC, 0xFFC4D2ED, 0xFFCDDBF4, 0xFFD1FFFE, 0xFFDDF7FF,
    ],
    foreground: 0xFFDDF7FF,
    background: 0xFF0B0C16,
    cursor: 0xFFDDF7FF,
    accent: 0xFF82FB9C,
    selection: 0xFF1F253A,
    style: ThemeStyle(
      shape: CornerShape.square,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.compact,
      appFont: 'jetbrains',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 8, showTabs: true),
      backdrop: BackdropStyle(dim: 0.3, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 2, labelFont: KeyLabelFont.terminal),
    ),
    backdrops: [BackdropPattern.scanlines, BackdropPattern.stars, BackdropPattern.dots],
  );

  static const ristretto = ThemeSpec(
    id: 'ristretto',
    name: 'Ristretto',
    builtIn: true,
    credit: 'Ristretto from Omarchy (MIT)',
    ansi: [
      0xFF2C2525, 0xFFFD6883, 0xFFADDA78, 0xFFF9CC6C, 0xFFF38D70, 0xFFA8A9EB, 0xFF85DACC, 0xFFE6D9DB, //
      0xFF72696A, 0xFFFF8297, 0xFFC8E292, 0xFFFCD675, 0xFFF8A788, 0xFFBEBFFD, 0xFF9BF1E1, 0xFFE6D9DB,
    ],
    foreground: 0xFFE6D9DB,
    background: 0xFF2C2525,
    cursor: 0xFFE6D9DB,
    accent: 0xFFF38D70,
    selection: 0xFF403E41,
    style: ThemeStyle(
      shape: CornerShape.rounded,
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
    backdrops: [BackdropPattern.mesh, BackdropPattern.topo],
  );

  static const synthwave84 = ThemeSpec(
    id: 'synthwave-84',
    name: 'Synthwave \'84',
    builtIn: true,
    credit: 'Synthwave \'84 by Robb Owen (MIT)',
    ansi: [
      0xFF262335, 0xFFFE4450, 0xFF72F1B8, 0xFFF3E70F, 0xFF03EDF9, 0xFFFF7EDB, 0xFF03EDF9, 0xFFFFFFFF, //
      0xFF614D85, 0xFFFE4450, 0xFF72F1B8, 0xFFFEDE5D, 0xFF03EDF9, 0xFFFF7EDB, 0xFF03EDF9, 0xFFFFFFFF,
    ],
    foreground: 0xFFFFFFFF,
    background: 0xFF262335,
    cursor: 0xFFFFFFFF,
    accent: 0xFFFF7EDB,
    style: ThemeStyle(
      shape: CornerShape.round,
      surface: SurfaceStyle.glass,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.floating,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 8, showTabs: true),
      backdrop: BackdropStyle(dim: 0.35, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.stars, BackdropPattern.mesh, BackdropPattern.facets],
  );

  static const vesper = ThemeSpec(
    id: 'vesper',
    name: 'Vesper',
    builtIn: true,
    credit: 'Vesper by Rauno Freiberg (MIT)',
    ansi: [
      0xFF101010, 0xFFF5A191, 0xFF90B99F, 0xFFE6B99D, 0xFFACA1CF, 0xFFE29ECA, 0xFFEA83A5, 0xFFA0A0A0, //
      0xFF7E7E7E, 0xFFFF8080, 0xFF99FFE4, 0xFFFFC799, 0xFFB9AEDA, 0xFFECAAD6, 0xFFF591B2, 0xFFFFFFFF,
    ],
    foreground: 0xFFFFFFFF,
    background: 0xFF101010,
    cursor: 0xFFFFFFFF,
    accent: 0xFFFFC799,
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.normal,
      appFont: 'plex',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 4, showTabs: false),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 4, labelFont: KeyLabelFont.terminal),
    ),
    backdrops: [BackdropPattern.dots, BackdropPattern.scanlines],
  );

  static const githubHighContrast = ThemeSpec(
    id: 'github-dark-high-contrast',
    name: 'GitHub High Contrast',
    builtIn: true,
    credit: 'GitHub Dark High Contrast, Primer colours (MIT)',
    ansi: [
      0xFF7A828E, 0xFFFF9492, 0xFF26CD4D, 0xFFF0B72F, 0xFF71B7FF, 0xFFCB9EFF, 0xFF39C5CF, 0xFFD9DEE3, //
      0xFF9EA7B3, 0xFFFFB1AF, 0xFF4AE168, 0xFFF7C843, 0xFF91CBFF, 0xFFCB9EFF, 0xFF39C5CF, 0xFFD9DEE3,
    ],
    foreground: 0xFFF0F3F6,
    background: 0xFF0A0C10,
    cursor: 0xFFF0F3F6,
    accent: 0xFF71B7FF,
    style: ThemeStyle(
      shape: CornerShape.square,
      surface: SurfaceStyle.flat,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.2,
      nav: NavStyle.labelled,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 8, showTabs: false),
      backdrop: BackdropStyle(dim: 0.85, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 6, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.dots, BackdropPattern.scanlines],
  );

  static const flexokiLight = ThemeSpec(
    id: 'flexoki-light',
    name: 'Flexoki Light',
    builtIn: true,
    credit: 'Flexoki by Steph Ango (MIT)',
    ansi: [
      0xFF100F0F, 0xFFD14D41, 0xFF879A39, 0xFFD0A215, 0xFF4385BE, 0xFFCE5D97, 0xFF3AA99F, 0xFFFFFCF0, //
      0xFF100F0F, 0xFFD14D41, 0xFF879A39, 0xFFD0A215, 0xFF4385BE, 0xFFCE5D97, 0xFF3AA99F, 0xFFFFFCF0,
    ],
    foreground: 0xFF100F0F,
    background: 0xFFFFFCF0,
    cursor: 0xFF100F0F,
    accent: 0xFF4385BE,
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.outlined,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.outlined,
      terminal: TerminalStyle(padding: 16, showTabs: false),
      backdrop: BackdropStyle(dim: 0.5, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.dots, BackdropPattern.topo],
  );

  static const rosePineDawn = ThemeSpec(
    id: 'rose-pine-dawn',
    name: 'Rosé Pine Dawn',
    builtIn: true,
    credit: 'Rosé Pine (MIT)',
    ansi: [
      0xFFF2E9E1, 0xFFB4637A, 0xFF286983, 0xFFEA9D34, 0xFF56949F, 0xFF907AA9, 0xFFD7827E, 0xFF575279, //
      0xFF9893A5, 0xFFB4637A, 0xFF286983, 0xFFEA9D34, 0xFF56949F, 0xFF907AA9, 0xFFD7827E, 0xFF575279,
    ],
    foreground: 0xFF575279,
    background: 0xFFFAF4ED,
    cursor: 0xFFCECACD,
    accent: 0xFF907AA9,
    selection: 0xFFDFDAD9,
    style: ThemeStyle(
      shape: CornerShape.round,
      surface: SurfaceStyle.raised,
      density: StyleDensity.comfortable,
      appFont: 'system',
      textScale: 1.1,
      nav: NavStyle.floating,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 16, showTabs: false),
      backdrop: BackdropStyle(dim: 0.4, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.raised, gap: 6, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.mesh, BackdropPattern.facets],
  );

  /// Early-2000s desktop: a beige window with near-white panes, a blue
  /// banded title bar and taskbar, shaded buttons and keys with an orange
  /// glow when pressed, a green start-style main button, and hills under
  /// a blue sky. The look is drawn in code; no logos, photos or fonts of
  /// that era's software are used.
  static const millennium = ThemeSpec(
    id: 'millennium',
    name: 'Millennium',
    builtIn: true,
    credit: 'Window colours from XP.css by Adam Hammad (MIT); console colours from the classic VGA palette',
    ansi: [
      0xFF000000, 0xFFA80000, 0xFF00A800, 0xFFA85400, 0xFF0000A8, 0xFFA800A8, 0xFF00A8A8, 0xFFA8A8A8, //
      0xFF545454, 0xFFFC5454, 0xFF54FC54, 0xFFFCFC54, 0xFF5454FC, 0xFFFC54FC, 0xFF54FCFC, 0xFFFFFFFF,
    ],
    foreground: 0xFF000000,
    background: 0xFFECE9D8,
    cursor: 0xFF000000,
    accent: 0xFF0053EE,
    selection: 0xFF2267CB,
    style: ThemeStyle(
      shape: CornerShape.soft,
      surface: SurfaceStyle.glossy,
      density: StyleDensity.normal,
      appFont: 'system',
      textScale: 1.0,
      nav: NavStyle.labelled,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 6, showTabs: true),
      backdrop: BackdropStyle(dim: 0.3, blur: 0),
      keys: KeysStyle(cap: KeyCapStyle.glossy, gap: 4, labelFont: KeyLabelFont.app),
    ),
    backdrops: [BackdropPattern.hills, BackdropPattern.dots],
  );

  static const all = [matteBlack, iceberg, oxocarbon, hackerman, ristretto, synthwave84, vesper, githubHighContrast, flexokiLight, rosePineDawn, millennium];
}
