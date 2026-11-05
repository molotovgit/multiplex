import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/app/theme_style.dart';
import 'package:multiplex/ui/appearance/theme_text_reader.dart';
import 'package:multiplex/ui/appearance/theme_text_writer.dart';

/// Reads text against a theme with two pictures in its folder.
abstract final class _Text {
  static final base = BuiltInThemes.tokyoNight.copyWith(id: 'mine', name: 'Mine', backgrounds: ['a.jpg', 'b.png'], activeBackground: 1);

  static ThemeTextResult read(String text) => ThemeTextReader(base: base, pictures: {'a.jpg', 'b.png'}).read(text);

  /// The written text with one exact piece swapped.
  static String edited(String from, String to) {
    final text = ThemeTextWriter.write(base);
    expect(text, contains(from), reason: 'the written text should contain $from');
    return text.replaceFirst(from, to);
  }

  /// The line number (from 1) of the first line containing [piece].
  static int lineOf(String text, String piece) => text.split('\n').indexWhere((l) => l.contains(piece)) + 1;
}

void main() {
  test('written text reads back to the same theme, notes and all', () {
    final text = ThemeTextWriter.write(_Text.base);
    expect(text, contains('// '));
    expect(text, contains('"shape": "soft"'));
    final result = _Text.read(text);
    expect(result.errors, isEmpty);
    final back = result.theme!;
    expect(back.toJson(), _Text.base.toJson());
  });

  test('every style choice round-trips through the text', () {
    const style = ThemeStyle(
      shape: CornerShape.round,
      surface: SurfaceStyle.glass,
      density: StyleDensity.comfortable,
      appFont: 'plex',
      textScale: 0.9,
      nav: NavStyle.rail,
      icons: IconStyle.filled,
      terminal: TerminalStyle(padding: 16, showTabs: true),
      backdrop: BackdropStyle(dim: 0.7, blur: 12, onScreens: true),
      keys: KeysStyle(cap: KeyCapStyle.flat, gap: 2, labelFont: KeyLabelFont.terminal),
    );
    final theme = _Text.base.copyWith(style: style);
    final back = ThemeTextReader(base: theme, pictures: {'a.jpg', 'b.png'}).read(ThemeTextWriter.write(theme));
    expect(back.theme?.style, style);
  });

  test('notes are ignored, but // inside text stays', () {
    final text = _Text.edited('"name": "Mine",', '"name": "Mine // two", // a note after the value');
    expect(_Text.read(text).theme?.name, 'Mine // two');
    expect(ThemeTextReader.stripNotes('{"a": 1} // note\n'), '{"a": 1}        \n');
  });

  test('a broken colour is reported on its own line', () {
    final text = _Text.edited('"accent": "#7aa2f7"', '"accent": "blue"');
    final result = _Text.read(text);
    expect(result.ok, isFalse);
    expect(result.errors.single.line, _Text.lineOf(text, '"accent"'));
    expect(result.errors.single.toString(), startsWith('Line ${_Text.lineOf(text, '"accent"')}: Write colours as'));
  });

  test('a missing comma is reported near where it is', () {
    final text = _Text.edited('"cursor": "#c0caf5",', '"cursor": "#c0caf5"');
    final result = _Text.read(text);
    expect(result.errors.single.message, contains('not valid JSON'));
    final cursorLine = _Text.lineOf(text, '"cursor"');
    expect(result.errors.single.line, inInclusiveRange(cursorLine, cursorLine + 3));
  });

  test('wrong style values, unknown keys and unknown pictures are each named', () {
    var text = _Text.edited('"shape": "soft"', '"shape": "blob"');
    text = text.replaceFirst('"gap": 4', '"gap": 5');
    text = text.replaceFirst('"name": "Mine"', '"name": "Mine",\n  "colour": "#ffffff"');
    text = text.replaceFirst('["a.jpg","b.png"]', '["a.jpg","missing.jpg"]');
    final result = _Text.read(text);
    final messages = result.errors.map((e) => e.message).join('\n');
    expect(messages, contains('"shape" must be one of: square, soft, rounded, round'));
    expect(messages, contains('"gap" must be one of: 2, 4, 6'));
    expect(messages, contains('does not know "colour"'));
    expect(messages, contains('"missing.jpg"'));
    expect(result.errors.firstWhere((e) => e.message.contains('shape')).line, _Text.lineOf(text, '"shape"'));
    expect(result.errors.firstWhere((e) => e.message.contains('gap')).line, _Text.lineOf(text, '"gap"'));
    // Problems are listed from the top of the text down.
    final lines = [for (final e in result.errors) e.line];
    expect(lines, [...lines]..sort());
  });

  test('the colour list needs 16 colours, and the picture number must fit', () {
    final text = _Text.edited('"activeBackground": 1', '"activeBackground": 9').replaceFirst('"#32344a", ', '');
    final messages = _Text.read(text).errors.map((e) => e.message).join('\n');
    expect(messages, contains('exactly 16 colours'));
    // Two drawn backdrops and two pictures: steps 0 to 4, the last the plain colour.
    expect(messages, contains('Use a number from 0 to 4'));
  });

  test('keys left out keep the theme\'s values', () {
    final result = _Text.read('{"name": "Short"}');
    expect(result.ok, isTrue);
    expect(result.theme!.name, 'Short');
    expect(result.theme!.background, _Text.base.background);
    expect(result.theme!.style, _Text.base.style);
    expect(_Text.read('[1, 2]').errors.single.message, contains('{ ... }'));
  });
}
