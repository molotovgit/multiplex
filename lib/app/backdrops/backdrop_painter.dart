import 'dart:math' as math;
import 'dart:ui';

import '../theme_spec.dart';
import '../theme_style.dart';
import 'backdrop_patterns.dart';

/// The colours a backdrop is drawn in, all taken from one theme.
class BackdropColors {
  const BackdropColors({required this.background, required this.ink, required this.accent, required this.hues, required this.seed});

  factory BackdropColors.of(ThemeSpec theme) => BackdropColors(
        background: Color(theme.background),
        ink: Color(theme.foreground),
        accent: Color(theme.accent),
        // Blue, magenta, cyan and green: the theme's own colourful notes.
        hues: [for (final i in const [4, 5, 6, 2]) Color(theme.ansi[i])],
        seed: _Fnv.hash(theme.id),
      );

  final Color background;

  /// Lines, dots and stars: the theme's text colour, used faintly.
  final Color ink;
  final Color accent;
  final List<Color> hues;

  /// The same theme always gets the same drawing.
  final int seed;

  @override
  bool operator ==(Object other) =>
      other is BackdropColors &&
      other.background == background &&
      other.ink == ink &&
      other.accent == accent &&
      other.seed == seed &&
      _sameHues(other.hues);

  bool _sameHues(List<Color> other) {
    if (other.length != hues.length) return false;
    for (var i = 0; i < hues.length; i++) {
      if (other[i] != hues[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(background, ink, accent, seed, Object.hashAll(hues));
}

/// A small, stable string hash, so drawings do not change between runs.
abstract final class _Fnv {
  static int hash(String text) {
    var h = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    return h;
  }
}

/// Draws one kind of backdrop. Sizes are in logical pixels, so a pattern
/// looks the same on every screen density. Drawings are quiet on purpose:
/// text sits on top of them.
abstract class BackdropPainter {
  const BackdropPainter();

  /// The painter for [pattern].
  factory BackdropPainter.of(BackdropPattern pattern) => switch (pattern) {
        BackdropPattern.mesh => const MeshPainter(),
        BackdropPattern.dots => const DotGridPainter(),
        BackdropPattern.scanlines => const ScanlinePainter(),
        BackdropPattern.topo => const TopoPainter(),
        BackdropPattern.facets => const FacetPainter(),
        BackdropPattern.stars => const StarfieldPainter(),
        BackdropPattern.hills => const HillsPainter(),
      };

  /// Fills [size] with the background colour, then draws the pattern.
  void paint(Canvas canvas, Size size, BackdropColors colors) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.background);
    draw(canvas, size, colors, math.Random(colors.seed));
  }

  /// The pattern itself, on top of the background colour.
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random);
}
