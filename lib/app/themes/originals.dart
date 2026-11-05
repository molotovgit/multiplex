import '../theme_spec.dart';
import '../theme_style.dart';

/// Multiplex's own themes. Ember is the app's signature and keeps its original look.
abstract final class OriginalThemes {
  static const ember = ThemeSpec(
    id: 'ember',
    name: 'Ember',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF1B1D1E, 0xFFE0605A, 0xFF8FBF6A, 0xFFE2B65C, 0xFF6B9BD8, 0xFFB78AD6, 0xFF5FB8B2, 0xFFD4D0C8, //
      0xFF5C6166, 0xFFF07F78, 0xFFA9D88A, 0xFFF3CD7E, 0xFF8DB6EA, 0xFFCDA8E6, 0xFF82D2CC, 0xFFF4F1EA,
    ],
    foreground: 0xFFE6E1D6,
    background: 0xFF141618,
    cursor: 0xFFF2B33D,
    accent: 0xFFF2B33D,
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

  static const slate = ThemeSpec(
    id: 'slate',
    name: 'Slate',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF1C2329, 0xFFE06C75, 0xFF7FC08A, 0xFFD9B96B, 0xFF6AA4E0, 0xFFB79BE3, 0xFF5CC4C9, 0xFFC9D1D9, //
      0xFF4F5B66, 0xFFF08A92, 0xFF9AD9A4, 0xFFEACF86, 0xFF8DBCF0, 0xFFCEB6F0, 0xFF7ED8DC, 0xFFEEF2F5,
    ],
    foreground: 0xFFD3DAE1,
    background: 0xFF111820,
    cursor: 0xFF7ED8DC,
    accent: 0xFF7ED8DC,
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

  static const matte = ThemeSpec(
    id: 'matte',
    name: 'Matte',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF161616, 0xFFD75F5F, 0xFF87AF87, 0xFFD7AF87, 0xFF87AFD7, 0xFFAF87AF, 0xFF87AFAF, 0xFFBCBCBC, //
      0xFF4E4E4E, 0xFFE07B7B, 0xFFA1C5A1, 0xFFE3C4A0, 0xFFA3C3E3, 0xFFC4A3C4, 0xFFA3C4C4, 0xFFEEEEEE,
    ],
    foreground: 0xFFD6D6D6,
    background: 0xFF0B0B0B,
    cursor: 0xFFEEEEEE,
    accent: 0xFFD0D0D0,
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

  static const phosphor = ThemeSpec(
    id: 'phosphor',
    name: 'Phosphor',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF0B1A0B, 0xFFFF6B4A, 0xFF39FF14, 0xFFD4FF5A, 0xFF5AFFB4, 0xFFB4FF7A, 0xFF7DFFC8, 0xFFA8FFA0, //
      0xFF2E5A2E, 0xFFFF8F73, 0xFF7CFF5C, 0xFFE8FF8F, 0xFF8FFFCB, 0xFFCCFF9E, 0xFFA6FFDB, 0xFFD9FFD4,
    ],
    foreground: 0xFF4AF626,
    background: 0xFF050A05,
    cursor: 0xFF7CFF5C,
    accent: 0xFF39FF14,
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

  static const espresso = ThemeSpec(
    id: 'espresso',
    name: 'Espresso',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF2B201A, 0xFFD9705A, 0xFFA3B36B, 0xFFE0A85C, 0xFF8FA8C8, 0xFFC48AA3, 0xFF8CBFAF, 0xFFD4C3AE, //
      0xFF5C4A3E, 0xFFE88E78, 0xFFBCCB88, 0xFFF0C07E, 0xFFABC0DC, 0xFFD8A6BD, 0xFFA8D4C6, 0xFFF5EBDD,
    ],
    foreground: 0xFFE8D9C5,
    background: 0xFF1E1612,
    cursor: 0xFFE0A85C,
    accent: 0xFFD99A5B,
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

  static const neon = ThemeSpec(
    id: 'neon',
    name: 'Neon',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF141A3A, 0xFFFF3D7F, 0xFF2BFF88, 0xFFFFE53D, 0xFF3DA5FF, 0xFFC63DFF, 0xFF2BF0FF, 0xFFC8D0F0, //
      0xFF3A4370, 0xFFFF6FA0, 0xFF6BFFAB, 0xFFFFF07A, 0xFF73C0FF, 0xFFD877FF, 0xFF73F6FF, 0xFFFFFFFF,
    ],
    foreground: 0xFFE0E6FF,
    background: 0xFF0A0E27,
    cursor: 0xFF2BF0FF,
    accent: 0xFFFF4FD8,
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

  static const mono = ThemeSpec(
    id: 'mono',
    name: 'Mono',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF1C1C1C, 0xFF8A8A8A, 0xFFB0B0B0, 0xFFC8C8C8, 0xFF9E9E9E, 0xFF767676, 0xFFBEBEBE, 0xFFD6D6D6, //
      0xFF4A4A4A, 0xFFA0A0A0, 0xFFC2C2C2, 0xFFDADADA, 0xFFB4B4B4, 0xFF8C8C8C, 0xFFD0D0D0, 0xFFF5F5F5,
    ],
    foreground: 0xFFE4E4E4,
    background: 0xFF121212,
    cursor: 0xFFF5F5F5,
    accent: 0xFFF0F0F0,
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

  static const contrast = ThemeSpec(
    id: 'contrast',
    name: 'High contrast',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF000000, 0xFFFF5555, 0xFF55FF55, 0xFFFFFF55, 0xFF5599FF, 0xFFFF55FF, 0xFF55FFFF, 0xFFE5E5E5, //
      0xFF7F7F7F, 0xFFFF8080, 0xFF80FF80, 0xFFFFFF80, 0xFF80B3FF, 0xFFFF80FF, 0xFF80FFFF, 0xFFFFFFFF,
    ],
    foreground: 0xFFFFFFFF,
    background: 0xFF000000,
    cursor: 0xFFFFD000,
    accent: 0xFFFFD000,
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

  static const paper = ThemeSpec(
    id: 'paper',
    name: 'Paper',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF2B2B2B, 0xFFB3261E, 0xFF3C7A2A, 0xFF8A6200, 0xFF2556A8, 0xFF7B3FA0, 0xFF1C7A78, 0xFFBDB8AE, //
      0xFF6B6B6B, 0xFFD0453C, 0xFF4F9A3A, 0xFFA87A10, 0xFF3A6FC8, 0xFF9658BF, 0xFF2A9693, 0xFFE8E4DA,
    ],
    foreground: 0xFF24262A,
    background: 0xFFF6F3EC,
    cursor: 0xFFA9670F,
    accent: 0xFFA9670F,
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

  static const pastel = ThemeSpec(
    id: 'pastel',
    name: 'Pastel',
    builtIn: true,
    credit: 'Multiplex',
    ansi: [
      0xFF4A4458, 0xFFC24F66, 0xFF3E8A5B, 0xFF9A6C14, 0xFF4A6FBF, 0xFF9555B0, 0xFF2E8585, 0xFFC9C2D6, //
      0xFF7A7290, 0xFFD9788C, 0xFF5FA57B, 0xFFB88B32, 0xFF6E8CD4, 0xFFAF7AC6, 0xFF4FA3A3, 0xFFEDE8F5,
    ],
    foreground: 0xFF4A4458,
    background: 0xFFFBF7FF,
    cursor: 0xFF9555B0,
    accent: 0xFF8A63D2,
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

  static const all = [ember, slate, matte, phosphor, espresso, neon, mono, contrast, paper, pastel];
}
