import 'dart:convert';

import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';
import 'color_tools.dart';

/// One "key": value line of the text, with a note above it.
class _Entry {
  const _Entry(this.key, this.value, [this.note]);

  final String key;

  /// A JSON value as text, or a [_Group] for a nested object.
  final Object value;
  final String? note;
}

/// A nested object, such as "style" or "keys".
class _Group {
  const _Group(this.entries);

  final List<_Entry> entries;
}

/// Writes a theme as readable JSON with notes ("// ...") that say what
/// each value does and which values are allowed. [ThemeTextReader] reads
/// it back; the notes are ignored there.
abstract final class ThemeTextWriter {
  static String _enumNote<T extends Enum>(List<T> values) => 'One of: ${values.map((v) => v.name).join(', ')}.';
  static String _numbers(List<double> values) => 'One of: ${values.map(_num).join(', ')}.';
  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
  static String _json(Object? v) => v is double ? _num(v) : jsonEncode(v);

  static String write(ThemeSpec theme) {
    final s = theme.style;
    final root = _Group([
      _Entry('name', _json(theme.name), 'Shown in the theme gallery.'),
      _Entry('background', _json(ColorHex.format(theme.background)), 'Colours are written #rrggbb. Behind the terminal and the app\'s screens.'),
      _Entry('foreground', _json(ColorHex.format(theme.foreground)), 'Normal terminal and app text.'),
      _Entry('cursor', _json(ColorHex.format(theme.cursor))),
      _Entry('accent', _json(ColorHex.format(theme.accent)), 'Buttons, tabs and highlights.'),
      _Entry('selection', _json(theme.selection == null ? null : ColorHex.format(theme.selection!)), 'Behind marked text; null uses the accent.'),
      _Entry('ansi', _ansi(theme.ansi), 'The 16 terminal colours: black, red, green, yellow, blue, magenta, cyan and white, then the same 8 bright.'),
      _Entry('style', _Group([
        _Entry('shape', _json(s.shape.name), 'Corners. ${_enumNote(CornerShape.values)}'),
        _Entry('surface', _json(s.surface.name), 'Cards and bars. ${_enumNote(SurfaceStyle.values)}'),
        _Entry('density', _json(s.density.name), _enumNote(StyleDensity.values)),
        _Entry('appFont', _json(s.appFont), '"system", "jetbrains", "plex", or the id of a font you added.'),
        _Entry('textScale', _json(s.textScale), _numbers(ThemeStyle.textScales)),
        _Entry('nav', _json(s.nav.name), 'Navigation. ${_enumNote(NavStyle.values)}'),
        _Entry('icons', _json(s.icons.name), _enumNote(IconStyle.values)),
        _Entry('terminal', _Group([
          _Entry('padding', _json(s.terminal.padding), 'Space around the text. ${_numbers(TerminalStyle.paddings)}'),
          _Entry('showTabs', _json(s.terminal.showTabs), 'true or false.'),
        ])),
        _Entry('backdrop', _Group([
          _Entry('dim', _json(s.backdrop.dim), 'How much the theme colour covers the pictures, 0 to ${_num(BackdropStyle.maxDim)}.'),
          _Entry('blur', _json(s.backdrop.blur), '0 to ${_num(BackdropStyle.maxBlur)}.'),
          _Entry('onScreens', _json(s.backdrop.onScreens), 'Pictures behind the main screens too: true or false.'),
        ])),
        _Entry('keys', _Group([
          _Entry('cap', _json(s.keys.cap.name), 'Keyboard keys. ${_enumNote(KeyCapStyle.values)}'),
          _Entry('gap', _json(s.keys.gap), _numbers(KeysStyle.gaps)),
          _Entry('labelFont', _json(s.keys.labelFont.name), _enumNote(KeyLabelFont.values)),
        ])),
      ]), 'The look of the elements.'),
      _Entry('backdrops', _json([for (final b in theme.backdrops) b.name]), 'Backdrops drawn from the colours. ${_enumNote(BackdropPattern.values)}'),
      _Entry('backgrounds', _json(theme.backgrounds), 'Pictures in this theme\'s folder. Next background shows the backdrops, then these, then the plain colour.'),
      _Entry('activeBackground', _json(theme.activeBackground), 'The step showing now, counting from 0.'),
    ]);
    final out = StringBuffer()
      ..writeln('// A Multiplex theme. Lines that start with // are notes; they are ignored.')
      ..writeln('// Save checks every value and points to the line of any problem.');
    _writeGroup(out, root, 0);
    out.writeln();
    return out.toString();
  }

  /// Eight colours to a line, normal then bright.
  static String _ansi(List<int> ansi) {
    String row(int from) => [for (var i = from; i < from + 8; i++) _json(ColorHex.format(ansi[i]))].join(', ');
    return '[\n  ${row(0)},\n  ${row(8)}\n]';
  }

  static void _writeGroup(StringBuffer out, _Group group, int depth) {
    final pad = '  ' * (depth + 1);
    out.write('{\n');
    for (final (i, entry) in group.entries.indexed) {
      if (entry.note != null) out.writeln('$pad// ${entry.note}');
      out.write('$pad"${entry.key}": ');
      final value = entry.value;
      if (value is _Group) {
        _writeGroup(out, value, depth + 1);
      } else {
        // Multi-line values (the colour list) are indented to match.
        out.write((value as String).replaceAll('\n', '\n$pad'));
      }
      out.write(i == group.entries.length - 1 ? '\n' : ',\n');
    }
    out.write('${'  ' * depth}}');
  }
}
