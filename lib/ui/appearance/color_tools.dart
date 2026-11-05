import 'package:flutter/painting.dart';

/// Turns colours into "#rrggbb" text and back.
abstract final class ColorHex {
  /// "#rrggbb" for a 0xAARRGGBB colour. The alpha part is left out.
  static String format(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Reads "#rrggbb", "rrggbb" or the short "#rgb". Returns an opaque
  /// 0xAARRGGBB colour, or null when the text is not a colour.
  static int? parse(String text) {
    var hex = text.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length != 6) return null;
    return 0xFF000000 | int.parse(hex, radix: 16);
  }
}

/// How readable one colour is on another, using the WCAG contrast ratio:
/// 1 means no difference at all, 21 is black on white.
abstract final class ColorContrast {
  /// Below this, normal-sized text is hard to read (the WCAG AA level).
  /// The editor warns about it.
  static const lowText = 4.5;

  /// Below this, an accent colour does not stand out from the background.
  static const lowAccent = 3.0;

  static double ratio(int a, int b) {
    final la = Color(a).computeLuminance();
    final lb = Color(b).computeLuminance();
    final light = la > lb ? la : lb;
    final dark = la > lb ? lb : la;
    return (light + 0.05) / (dark + 0.05);
  }
}

/// The names of the 16 terminal colours, in palette order.
abstract final class AnsiNames {
  static const normal = ['Black', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White'];

  /// "Red" for 1, "Bright red" for 9.
  static String of(int index) {
    final base = normal[index % 8];
    return index < 8 ? base : 'Bright ${base.toLowerCase()}';
  }
}
