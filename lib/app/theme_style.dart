import '../data/models.dart';

/// How round the corners of cards, buttons, fields, sheets, dialogs, chips
/// and keyboard keys are.
enum CornerShape {
  square('Square', 0),
  soft('Soft', 6),
  rounded('Rounded', 14),
  round('Round', 24);

  const CornerShape(this.label, this.radius);

  final String label;

  /// Corner radius of a card, in logical pixels.
  final double radius;
}

/// How cards, bars and sheets stand out from the background.
enum SurfaceStyle {
  flat('Flat', 'No border, no shadow'),
  outlined('Outlined', 'A thin border'),
  raised('Raised', 'A soft shadow'),
  glass('Glass', 'See-through, with blur');

  const SurfaceStyle(this.label, this.description);

  final String label;
  final String description;
}

/// How much room controls and list rows take.
enum StyleDensity {
  compact('Compact'),
  normal('Normal'),
  comfortable('Comfortable');

  const StyleDensity(this.label);

  final String label;
}

/// How the five main places are reached.
enum NavStyle {
  labelled('Bottom bar', 'Icons with labels'),
  iconsOnly('Icons only', 'A bottom bar without labels'),
  floating('Floating bar', 'A rounded bar above the content'),
  rail('Side rail', 'Along the left edge, on phones too');

  const NavStyle(this.label, this.description);

  final String label;
  final String description;
}

/// Outlined or filled icons across the app.
enum IconStyle {
  outlined('Outlined'),
  filled('Filled');

  const IconStyle(this.label);

  final String label;
}

/// How keyboard keys stand out from the keyboard panel.
enum KeyCapStyle {
  flat('Flat'),
  outlined('Outlined'),
  raised('Raised');

  const KeyCapStyle(this.label);

  final String label;
}

/// Which font the keyboard's key labels use.
enum KeyLabelFont {
  app('App font'),
  terminal('Terminal font');

  const KeyLabelFont(this.label);

  final String label;
}

/// Reads enum values from JSON, falling back when the name is unknown.
abstract final class _Enum {
  static T read<T extends Enum>(List<T> values, Object? name, T fallback) => values.asNameMap()[name] ?? fallback;

  /// The allowed value nearest to [value], so odd numbers in an imported
  /// theme snap to one the controls can show.
  static double nearest(Object? value, List<double> allowed, double fallback) {
    if (value is! num) return fallback;
    var best = allowed.first;
    for (final a in allowed) {
      if ((a - value).abs() < (best - value).abs()) best = a;
    }
    return best;
  }
}

/// The look of the terminal screen.
class TerminalStyle {
  const TerminalStyle({this.padding = 4, this.backgroundImage, this.dim = 0.4, this.blur = 0, this.showTabs = false});

  /// Space between the screen edge and the text.
  final double padding;

  /// File name of a picture in the app's backgrounds folder, or null.
  final String? backgroundImage;

  /// How much the picture is covered by the theme's background, 0 to 0.9.
  final double dim;

  /// Blur of the picture, 0 to 20.
  final double blur;

  /// Shows a strip of the connection's terminals above the text.
  final bool showTabs;

  static const paddings = [0.0, 4.0, 8.0, 16.0];
  static const maxDim = 0.9;
  static const maxBlur = 20.0;

  bool get hasImage => backgroundImage != null;

  TerminalStyle copyWith({double? padding, String? Function()? backgroundImage, double? dim, double? blur, bool? showTabs}) =>
      TerminalStyle(
        padding: padding ?? this.padding,
        backgroundImage: backgroundImage != null ? backgroundImage() : this.backgroundImage,
        dim: (dim ?? this.dim).clamp(0.0, maxDim),
        blur: (blur ?? this.blur).clamp(0.0, maxBlur),
        showTabs: showTabs ?? this.showTabs,
      );

  Map<String, dynamic> toJson() => {
        'padding': padding,
        'backgroundImage': backgroundImage,
        'dim': dim,
        'blur': blur,
        'showTabs': showTabs,
      };

  factory TerminalStyle.fromJson(Map<String, dynamic> j) {
    const d = TerminalStyle();
    double number(String key, double fallback, double max) => j[key] is num ? (j[key] as num).toDouble().clamp(0.0, max) : fallback;
    return TerminalStyle(
      padding: _Enum.nearest(j['padding'], paddings, d.padding),
      backgroundImage: safeFileName(j['backgroundImage']),
      dim: number('dim', d.dim, maxDim),
      blur: number('blur', d.blur, maxBlur),
      showTabs: Json.boolean(j, 'showTabs', d.showTabs),
    );
  }

  /// Themes can come from anywhere, so only a plain file name is kept:
  /// nothing that could point outside the backgrounds folder.
  static String? safeFileName(Object? value) {
    if (value is! String) return null;
    final name = value.trim();
    if (name.isEmpty || name.length > 128 || name.startsWith('.')) return null;
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) return null;
    return name;
  }

  @override
  bool operator ==(Object other) =>
      other is TerminalStyle &&
      other.padding == padding &&
      other.backgroundImage == backgroundImage &&
      other.dim == dim &&
      other.blur == blur &&
      other.showTabs == showTabs;

  @override
  int get hashCode => Object.hash(padding, backgroundImage, dim, blur, showTabs);
}

/// The look of the built-in keyboard's keys.
class KeysStyle {
  const KeysStyle({this.cap = KeyCapStyle.raised, this.gap = 4, this.labelFont = KeyLabelFont.app});

  final KeyCapStyle cap;

  /// Space around each key, in logical pixels: 2, 4 or 6.
  final double gap;
  final KeyLabelFont labelFont;

  static const gaps = [2.0, 4.0, 6.0];

  KeysStyle copyWith({KeyCapStyle? cap, double? gap, KeyLabelFont? labelFont}) =>
      KeysStyle(cap: cap ?? this.cap, gap: gap ?? this.gap, labelFont: labelFont ?? this.labelFont);

  Map<String, dynamic> toJson() => {'cap': cap.name, 'gap': gap, 'labelFont': labelFont.name};

  factory KeysStyle.fromJson(Map<String, dynamic> j) {
    const d = KeysStyle();
    return KeysStyle(
      cap: _Enum.read(KeyCapStyle.values, j['cap'], d.cap),
      gap: _Enum.nearest(j['gap'], gaps, d.gap),
      labelFont: _Enum.read(KeyLabelFont.values, j['labelFont'], d.labelFont),
    );
  }

  @override
  bool operator ==(Object other) => other is KeysStyle && other.cap == cap && other.gap == gap && other.labelFont == labelFont;

  @override
  int get hashCode => Object.hash(cap, gap, labelFont);
}

/// Everything about a theme's look apart from its colours: corners,
/// surfaces, density, fonts, navigation, icons, terminal and keyboard.
/// The defaults are Multiplex's original look.
class ThemeStyle {
  const ThemeStyle({
    this.shape = CornerShape.rounded,
    this.surface = SurfaceStyle.outlined,
    this.density = StyleDensity.normal,
    this.appFont = systemFont,
    this.textScale = 1.0,
    this.nav = NavStyle.labelled,
    this.icons = IconStyle.outlined,
    this.terminal = const TerminalStyle(),
    this.keys = const KeysStyle(),
  });

  final CornerShape shape;
  final SurfaceStyle surface;
  final StyleDensity density;

  /// [systemFont], a bundled font id or the id of a font the user added.
  final String appFont;

  /// Size of the app's text, as a multiple of the normal size.
  final double textScale;
  final NavStyle nav;
  final IconStyle icons;
  final TerminalStyle terminal;
  final KeysStyle keys;

  /// The platform's own font for the app's screens.
  static const systemFont = 'system';
  static const textScales = [0.9, 1.0, 1.1, 1.2];

  ThemeStyle copyWith({
    CornerShape? shape,
    SurfaceStyle? surface,
    StyleDensity? density,
    String? appFont,
    double? textScale,
    NavStyle? nav,
    IconStyle? icons,
    TerminalStyle? terminal,
    KeysStyle? keys,
  }) =>
      ThemeStyle(
        shape: shape ?? this.shape,
        surface: surface ?? this.surface,
        density: density ?? this.density,
        appFont: appFont ?? this.appFont,
        textScale: textScale ?? this.textScale,
        nav: nav ?? this.nav,
        icons: icons ?? this.icons,
        terminal: terminal ?? this.terminal,
        keys: keys ?? this.keys,
      );

  Map<String, dynamic> toJson() => {
        'shape': shape.name,
        'surface': surface.name,
        'density': density.name,
        'appFont': appFont,
        'textScale': textScale,
        'nav': nav.name,
        'icons': icons.name,
        'terminal': terminal.toJson(),
        'keys': keys.toJson(),
      };

  /// Missing or unknown values fall back to the defaults, so themes made
  /// before styles existed, or by another version, still load.
  factory ThemeStyle.fromJson(Object? json) {
    if (json is! Map) return const ThemeStyle();
    final j = json.cast<String, dynamic>();
    const d = ThemeStyle();
    final font = j['appFont'] is String ? (j['appFont'] as String).trim() : '';
    Map<String, dynamic> part(String key) => j[key] is Map ? (j[key] as Map).cast<String, dynamic>() : const {};
    return ThemeStyle(
      shape: _Enum.read(CornerShape.values, j['shape'], d.shape),
      surface: _Enum.read(SurfaceStyle.values, j['surface'], d.surface),
      density: _Enum.read(StyleDensity.values, j['density'], d.density),
      appFont: font.isEmpty || font.length > 64 ? d.appFont : font,
      textScale: _Enum.nearest(j['textScale'], textScales, d.textScale),
      nav: _Enum.read(NavStyle.values, j['nav'], d.nav),
      icons: _Enum.read(IconStyle.values, j['icons'], d.icons),
      terminal: TerminalStyle.fromJson(part('terminal')),
      keys: KeysStyle.fromJson(part('keys')),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeStyle &&
      other.shape == shape &&
      other.surface == surface &&
      other.density == density &&
      other.appFont == appFont &&
      other.textScale == textScale &&
      other.nav == nav &&
      other.icons == icons &&
      other.terminal == terminal &&
      other.keys == keys;

  @override
  int get hashCode => Object.hash(shape, surface, density, appFont, textScale, nav, icons, terminal, keys);
}
