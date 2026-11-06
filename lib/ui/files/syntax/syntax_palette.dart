import 'package:flutter/painting.dart';

import '../../../app/theme_spec.dart';
import 'syntax_tokenizer.dart';

/// The editor's colours, taken from the terminal theme's 16 ANSI colours
/// so code looks the way it does in the terminal. A colour too close to
/// the background is moved towards the text colour until it reads.
class SyntaxPalette {
  SyntaxPalette._(this._styles);

  factory SyntaxPalette.fromTheme(ThemeSpec theme) {
    final background = Color(theme.background);
    final foreground = Color(theme.foreground);
    Color ansi(int i) => readable(Color(theme.ansi[i]), background, foreground);
    return SyntaxPalette._({
      SyntaxToken.comment: TextStyle(color: ansi(8), fontStyle: FontStyle.italic),
      SyntaxToken.string: TextStyle(color: ansi(2)),
      SyntaxToken.number: TextStyle(color: ansi(3)),
      SyntaxToken.keyword: TextStyle(color: ansi(5)),
      SyntaxToken.constant: TextStyle(color: ansi(3)),
      SyntaxToken.key: TextStyle(color: ansi(6)),
      SyntaxToken.variable: TextStyle(color: ansi(4)),
      SyntaxToken.heading: TextStyle(color: ansi(12), fontWeight: FontWeight.w700),
      SyntaxToken.error: TextStyle(color: ansi(1), fontWeight: FontWeight.w700),
      SyntaxToken.warning: TextStyle(color: ansi(3), fontWeight: FontWeight.w700),
      SyntaxToken.info: TextStyle(color: ansi(2)),
      SyntaxToken.strong: const TextStyle(fontWeight: FontWeight.w700),
      SyntaxToken.code: TextStyle(color: ansi(2)),
    });
  }

  final Map<SyntaxToken, TextStyle> _styles;

  TextStyle style(SyntaxToken token) => _styles[token]!;

  /// Smallest contrast a coloured word keeps against the background.
  static const minContrast = 3.0;

  /// [color], or a mix of it with [foreground] that reaches [minContrast]
  /// on [background].
  static Color readable(Color color, Color background, Color foreground) {
    for (var t = 0.0; t <= 1.0; t += 0.1) {
      final mixed = Color.lerp(color, foreground, t)!;
      if (contrast(mixed, background) >= minContrast) return mixed;
    }
    return foreground;
  }

  /// The WCAG contrast ratio of two colours, from 1 to 21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final (hi, lo) = la > lb ? (la, lb) : (lb, la);
    return (hi + 0.05) / (lo + 0.05);
  }
}
