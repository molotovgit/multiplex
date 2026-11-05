import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';

/// The terminal font as a text style, for input fields that hold keys or
/// commands (MonoText covers text that is only shown).
abstract final class MonoStyle {
  static TextStyle of(BuildContext context, [TextStyle? base]) {
    final settings = AppScope.store(context).settings;
    final family = TerminalFonts.byId(settings, settings.terminalFontId).family;
    return (base ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(fontFamily: family, letterSpacing: 0);
  }
}
