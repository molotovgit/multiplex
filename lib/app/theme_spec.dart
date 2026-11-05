import 'dart:typed_data';

import '../data/models.dart';
import '../src/rust/api/terminal_types.dart';
import 'theme_style.dart';
import 'themes/dark.dart';
import 'themes/light.dart';
import 'themes/originals.dart';

/// One step of "Next background": a drawn backdrop or a picture. The
/// plain theme colour is the step after the last one.
sealed class ThemeSlide {
  const ThemeSlide();
}

class PatternSlide extends ThemeSlide {
  const PatternSlide(this.pattern);

  final BackdropPattern pattern;

  @override
  bool operator ==(Object other) => other is PatternSlide && other.pattern == pattern;

  @override
  int get hashCode => pattern.hashCode;
}

class PictureSlide extends ThemeSlide {
  const PictureSlide(this.name);

  /// File name in the theme's own folder.
  final String name;

  @override
  bool operator ==(Object other) => other is PictureSlide && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// One theme for the whole app: the terminal colours plus an accent, and
/// a [ThemeStyle] for the look of the elements (corners, surfaces,
/// navigation, fonts, terminal and keyboard). The app's own surfaces are
/// derived from these (see [AppColors.derive]), so switching a theme
/// restyles everything at once, terminal and screens alike.
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
    this.style = const ThemeStyle(),
    this.backgrounds = const [],
    this.backdrops = const [],
    this.activeBackground = 0,
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

  /// The look of the elements; colours stay in the fields above.
  final ThemeStyle style;

  /// File names of the theme's background pictures, kept in the theme's
  /// own folder (see ThemeBackgrounds). Built-in themes have none.
  final List<String> backgrounds;

  /// Backdrops drawn from the theme's colours, shown before the pictures.
  final List<BackdropPattern> backdrops;

  /// Which step of [slides] shows now, where [slides].length means the
  /// plain colour; "Next background" moves it on.
  final int activeBackground;

  /// The drawn backdrops, then the pictures.
  List<ThemeSlide> get slides => [for (final p in backdrops) PatternSlide(p), for (final n in backgrounds) PictureSlide(n)];

  /// Steps "Next background" moves through: every slide plus the plain
  /// colour, or none at all for a theme without slides.
  int get slideCount => backdrops.length + backgrounds.length == 0 ? 0 : backdrops.length + backgrounds.length + 1;

  /// The slide at step [index], or null for the plain colour.
  ThemeSlide? slideAt(int index) {
    final all = slides;
    if (all.isEmpty) return null;
    final i = index % (all.length + 1);
    return i < all.length ? all[i] : null;
  }

  /// The most pictures one theme keeps.
  static const maxBackgrounds = 30;

  /// The step of [activeBackground]: a backdrop, a picture or null for
  /// the plain colour.
  ThemeSlide? get currentSlide => slideAt(activeBackground);

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

  ThemeSpec copyWith({String? id, String? name, List<int>? ansi, int? foreground, int? background, int? cursor, int? accent, int? Function()? selection, ThemeStyle? style,
          String? credit, List<String>? backgrounds, List<BackdropPattern>? backdrops, int? activeBackground}) =>
      ThemeSpec(
        id: id ?? this.id,
        name: name ?? this.name,
        ansi: ansi ?? this.ansi,
        foreground: foreground ?? this.foreground,
        background: background ?? this.background,
        cursor: cursor ?? this.cursor,
        accent: accent ?? this.accent,
        selection: selection != null ? selection() : this.selection,
        credit: credit ?? this.credit,
        style: style ?? this.style,
        backgrounds: backgrounds ?? this.backgrounds,
        backdrops: backdrops ?? this.backdrops,
        // A new picture list starts at its first step.
        activeBackground: activeBackground ?? (backgrounds != null ? 0 : this.activeBackground),
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
        'credit': credit,
        'style': style.toJson(),
        'backgrounds': backgrounds,
        'backdrops': [for (final b in backdrops) b.name],
        'activeBackground': activeBackground,
      };

  factory ThemeSpec.fromJson(Map<String, dynamic> j) {
    final ansi = (j['ansi'] is List ? (j['ansi'] as List).whereType<num>().map((e) => e.toInt()).toList() : <int>[]);
    final fg = Json.integer(j, 'foreground', 0xFFE6E1D6);
    final backgrounds = j['backgrounds'] is List
        ? (j['backgrounds'] as List).map(SafeFileName.of).whereType<String>().take(maxBackgrounds).toList()
        : <String>[];
    final backdrops = j['backdrops'] is List
        ? (j['backdrops'] as List).map((n) => BackdropPattern.values.asNameMap()[n]).whereType<BackdropPattern>().toList()
        : <BackdropPattern>[];
    final steps = backgrounds.length + backdrops.length;
    return ThemeSpec(
      id: Json.str(j, 'id'),
      name: Json.str(j, 'name', 'Custom theme'),
      ansi: List.generate(16, (i) => i < ansi.length ? ansi[i] : (i >= 8 && i - 8 < ansi.length ? ansi[i - 8] : fg)),
      foreground: fg,
      background: Json.integer(j, 'background', 0xFF141618),
      cursor: Json.integer(j, 'cursor', fg),
      accent: Json.integer(j, 'accent', 0xFFF2B33D),
      selection: j['selection'] is num ? (j['selection'] as num).toInt() : null,
      credit: Json.strOrNull(j, 'credit'),
      style: ThemeStyle.fromJson(j['style']),
      backgrounds: backgrounds,
      backdrops: backdrops,
      // The step after the last slide is the plain colour, so it is allowed.
      activeBackground: Json.integer(j, 'activeBackground', 0).clamp(0, steps),
    );
  }
}

/// The themes that come with Multiplex, in gallery order: Multiplex's
/// own themes, then dark open-source schemes, then light ones. Each has a
/// full look of its own (see [ThemeSpec.style]) and backdrops drawn from
/// its colours.
abstract final class BuiltInThemes {
  static const ember = OriginalThemes.ember;
  static const slate = OriginalThemes.slate;
  static const matte = OriginalThemes.matte;
  static const phosphor = OriginalThemes.phosphor;
  static const espresso = OriginalThemes.espresso;
  static const neon = OriginalThemes.neon;
  static const mono = OriginalThemes.mono;
  static const contrast = OriginalThemes.contrast;
  static const paper = OriginalThemes.paper;
  static const pastel = OriginalThemes.pastel;
  static const tokyoNight = DarkThemes.tokyoNight;
  static const catppuccinMocha = DarkThemes.catppuccinMocha;
  static const gruvboxDark = DarkThemes.gruvboxDark;
  static const nord = DarkThemes.nord;
  static const everforest = DarkThemes.everforest;
  static const kanagawa = DarkThemes.kanagawa;
  static const rosePine = DarkThemes.rosePine;
  static const dracula = DarkThemes.dracula;
  static const solarizedDark = DarkThemes.solarizedDark;
  static const oneDark = DarkThemes.oneDark;
  static const ayuDark = DarkThemes.ayuDark;
  static const nightOwl = DarkThemes.nightOwl;
  static const catppuccinLatte = LightThemes.catppuccinLatte;
  static const solarizedLight = LightThemes.solarizedLight;
  static const gruvboxLight = LightThemes.gruvboxLight;
  static const ayuLight = LightThemes.ayuLight;

  static const all = [...OriginalThemes.all, ...DarkThemes.all, ...LightThemes.all];

  static const defaultId = 'ember';
}
