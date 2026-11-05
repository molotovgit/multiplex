import 'package:flutter/painting.dart';

import 'theme_spec.dart';

/// How selected terminal text looks in a theme: a solid fill, and one text
/// colour that reads on it.
///
/// The fill is the scheme's own selection colour, or else its accent at a
/// little under half strength over the background. Drawing the selected text in its
/// own colours would leave some of them unreadable, for example a grey
/// "magenta" on a grey fill, so all selected text takes one colour: the
/// theme's text colour when it reads well enough, otherwise its background,
/// white or black, whichever reads best.
class SelectionLook {
  const SelectionLook({required this.fill, required this.text});

  factory SelectionLook.of(ThemeSpec theme) {
    final background = Color(theme.background);
    // A scheme's own selection colour is made to be used as it is; the
    // accent is far too strong, so it is laid over the background lightly.
    final own = theme.selection;
    final fill = own != null ? Color(own).withValues(alpha: 1) : Color.alphaBlend(Color(theme.accent).withValues(alpha: strength), background);
    return SelectionLook(fill: fill, text: readableOn(fill, [Color(theme.foreground), background]));
  }

  /// How much of the accent shows over the background when the scheme has
  /// no selection colour of its own.
  static const strength = 0.45;

  /// The contrast selected text keeps at least (WCAG AA for normal text).
  static const minContrast = 4.5;

  final Color fill;
  final Color text;

  /// The first of [preferred] that reaches [minContrast] on [fill], or else
  /// whichever of them, white and black reads best.
  static Color readableOn(Color fill, List<Color> preferred) {
    for (final c in preferred) {
      if (contrast(c, fill) >= minContrast) return c.withValues(alpha: 1);
    }
    final all = [...preferred, const Color(0xFFFFFFFF), const Color(0xFF000000)];
    all.sort((a, b) => contrast(b, fill).compareTo(contrast(a, fill)));
    return all.first.withValues(alpha: 1);
  }

  /// WCAG contrast ratio of two opaque colours, from 1 to 21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  @override
  bool operator ==(Object other) => other is SelectionLook && other.fill == fill && other.text == text;

  @override
  int get hashCode => Object.hash(fill, text);
}
