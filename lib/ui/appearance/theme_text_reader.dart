import 'dart:convert';

import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';
import 'color_tools.dart';

/// One problem in theme text, with the line it is on.
class ThemeTextError {
  const ThemeTextError(this.line, this.message);

  /// Counting from 1, like an editor.
  final int line;
  final String message;

  @override
  String toString() => 'Line $line: $message';
}

/// The theme read from text, or the problems that stopped it.
class ThemeTextResult {
  const ThemeTextResult({this.theme, this.errors = const []});

  final ThemeSpec? theme;
  final List<ThemeTextError> errors;

  bool get ok => theme != null && errors.isEmpty;
}

/// Finds the line of a key in the text, for error messages.
class _Lines {
  _Lines(this.text);

  final String text;

  int lineAt(int offset) => '\n'.allMatches(text.substring(0, offset.clamp(0, text.length))).length + 1;

  /// The line of the last key in [path] that can be found, each one
  /// searched for after the one before it ("style", then "keys", ...).
  int of(List<String> path) {
    var from = 0, found = 0;
    for (final key in path) {
      final match = RegExp('"${RegExp.escape(key)}"\\s*:').allMatches(text, from).firstOrNull;
      if (match == null) break;
      from = match.end;
      found = match.start;
    }
    return lineAt(found);
  }
}

/// Reads the text [ThemeTextWriter] writes, after the user edited it.
/// Strict on purpose: a value the app cannot use is reported on its line
/// instead of being quietly replaced.
class ThemeTextReader {
  ThemeTextReader({required this.base, required this.pictures});

  /// The theme being edited; keys left out keep its values.
  final ThemeSpec base;

  /// The pictures in the theme's folder.
  final Set<String> pictures;

  final _errors = <ThemeTextError>[];
  late _Lines _lines;

  static const _topKeys = {
    'name', 'background', 'foreground', 'cursor', 'accent', 'selection', 'ansi', 'style', 'backdrops', 'backgrounds', 'activeBackground', //
    'id', 'credit',
  };

  ThemeTextResult read(String text) {
    _errors.clear();
    final clean = stripNotes(text);
    _lines = _Lines(clean);
    final Object? data;
    try {
      data = jsonDecode(clean);
    } on FormatException catch (e) {
      final line = e.offset == null ? 1 : _lines.lineAt(e.offset!);
      return ThemeTextResult(errors: [ThemeTextError(line, 'This is not valid JSON here. Check for a missing comma, quote or bracket.')]);
    }
    if (data is! Map<String, dynamic>) {
      return const ThemeTextResult(errors: [ThemeTextError(1, 'The theme must be one { ... } block.')]);
    }
    final json = data;
    _unknownKeys(json, _topKeys, const []);
    final name = json.containsKey('name') ? _string(json['name'], ['name']) : base.name;
    final ansi = json.containsKey('ansi') ? _ansi(json['ansi']) : base.ansi;
    final style = json.containsKey('style') ? _style(json['style']) : base.style;
    final backgrounds = json.containsKey('backgrounds') ? _backgrounds(json['backgrounds']) : base.backgrounds;
    final backdrops = json.containsKey('backdrops') ? _backdrops(json['backdrops']) : base.backdrops;
    final active = json.containsKey('activeBackground') ? _int(json['activeBackground'], ['activeBackground']) : base.activeBackground;
    final steps = (backgrounds?.length ?? 0) + (backdrops?.length ?? 0);
    if (active != null && (active < 0 || active > steps)) {
      _error(['activeBackground'], 'Use a number from 0 to $steps.');
    }
    int? color(String key, int fallback) => json.containsKey(key) ? _color(json[key], [key]) : fallback;
    final background = color('background', base.background), foreground = color('foreground', base.foreground);
    final cursor = color('cursor', base.cursor), accent = color('accent', base.accent);
    final selection = json.containsKey('selection') ? (json['selection'] == null ? null : _color(json['selection'], ['selection'])) : base.selection;
    final credit = json['credit'] is String ? json['credit'] as String : base.credit;
    if (name != null && name.trim().isEmpty) _error(['name'], 'Give the theme a name.');
    if (_errors.isNotEmpty) return ThemeTextResult(errors: [..._errors]..sort((a, b) => a.line.compareTo(b.line)));
    return ThemeTextResult(
      theme: base.copyWith(
        name: name!.trim(),
        ansi: ansi,
        background: background,
        foreground: foreground,
        cursor: cursor,
        accent: accent,
        selection: () => selection,
        style: style,
        credit: credit,
        backgrounds: backgrounds,
        backdrops: backdrops,
        activeBackground: active,
      ),
    );
  }

  /// Blanks out "// notes" outside strings, keeping every line and column
  /// where it was so error lines stay right.
  static String stripNotes(String text) {
    final out = StringBuffer();
    var inString = false, escaped = false, inNote = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inNote) {
        if (c == '\n') {
          inNote = false;
          out.write(c);
        } else {
          out.write(' ');
        }
        continue;
      }
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '"') {
        inString = true;
      } else if (c == '/' && i + 1 < text.length && text[i + 1] == '/') {
        inNote = true;
        out.write(' ');
        continue;
      }
      out.write(c);
    }
    return out.toString();
  }

  void _error(List<String> path, String message) => _errors.add(ThemeTextError(_lines.of(path), message));

  void _unknownKeys(Map<String, dynamic> map, Set<String> known, List<String> path) {
    for (final key in map.keys) {
      if (!known.contains(key)) _error([...path, key], 'Multiplex does not know "$key". Check the spelling, or remove it.');
    }
  }

  String? _string(Object? v, List<String> path) {
    if (v is String) return v;
    _error(path, 'Write this as text in quotes.');
    return null;
  }

  int? _int(Object? v, List<String> path) {
    if (v is int) return v;
    _error(path, 'Write this as a whole number.');
    return null;
  }

  int? _color(Object? v, List<String> path) {
    final value = v is String ? ColorHex.parse(v) : null;
    if (value == null) _error(path, 'Write colours as "#rrggbb", for example "#1a1b26".');
    return value;
  }

  List<int>? _ansi(Object? v) {
    if (v is! List || v.length != 16) {
      _error(['ansi'], 'List exactly 16 colours: 8 normal, then 8 bright.');
      return null;
    }
    final colors = [for (final c in v) c is String ? ColorHex.parse(c) : null];
    final bad = colors.indexWhere((c) => c == null);
    if (bad >= 0) {
      _error(['ansi'], 'Colour ${bad + 1} in the list is not a "#rrggbb" colour.');
      return null;
    }
    return colors.cast<int>();
  }

  List<String>? _backgrounds(Object? v) {
    if (v is! List) {
      _error(['backgrounds'], 'List the picture names in [ ], or leave the list empty.');
      return null;
    }
    final names = <String>[];
    for (final item in v) {
      if (item is! String || !pictures.contains(item)) {
        _error(['backgrounds'], 'There is no picture called ${jsonEncode(item)} in this theme\'s folder. Add pictures in the theme editor.');
      } else {
        names.add(item);
      }
    }
    return names;
  }

  List<BackdropPattern>? _backdrops(Object? v) {
    final names = BackdropPattern.values.asNameMap();
    if (v is! List || v.any((n) => !names.containsKey(n))) {
      _error(['backdrops'], 'List backdrops from: ${BackdropPattern.values.map((b) => b.name).join(', ')}.');
      return null;
    }
    return [for (final n in v) names[n]!];
  }

  ThemeStyle? _style(Object? v) {
    if (v is! Map<String, dynamic>) {
      _error(['style'], 'The style must be a { ... } block.');
      return null;
    }
    const groups = {'terminal', 'backdrop', 'keys'};
    _unknownKeys(v, {'shape', 'surface', 'density', 'appFont', 'textScale', 'nav', 'icons', ...groups}, ['style']);
    _choice(v, 'shape', CornerShape.values, ['style']);
    _choice(v, 'surface', SurfaceStyle.values, ['style']);
    _choice(v, 'density', StyleDensity.values, ['style']);
    _choice(v, 'nav', NavStyle.values, ['style']);
    _choice(v, 'icons', IconStyle.values, ['style']);
    if (v.containsKey('appFont')) _string(v['appFont'], ['style', 'appFont']);
    _number(v, 'textScale', ['style'], allowed: ThemeStyle.textScales);
    final merged = base.style.toJson();
    for (final entry in v.entries) {
      if (groups.contains(entry.key)) continue;
      merged[entry.key] = entry.value;
    }
    for (final group in groups) {
      final part = v[group];
      if (part == null) continue;
      if (part is! Map<String, dynamic>) {
        _error(['style', group], 'Write "$group" as a { ... } block.');
        continue;
      }
      _group(group, part);
      merged[group] = {...(merged[group] as Map<String, dynamic>), ...part};
    }
    return ThemeStyle.fromJson(merged);
  }

  void _group(String group, Map<String, dynamic> part) {
    final path = ['style', group];
    switch (group) {
      case 'terminal':
        _unknownKeys(part, {'padding', 'showTabs'}, path);
        _number(part, 'padding', path, allowed: TerminalStyle.paddings);
        _bool(part, 'showTabs', path);
      case 'backdrop':
        _unknownKeys(part, {'dim', 'blur', 'onScreens'}, path);
        _number(part, 'dim', path, max: BackdropStyle.maxDim);
        _number(part, 'blur', path, max: BackdropStyle.maxBlur);
        _bool(part, 'onScreens', path);
      case 'keys':
        _unknownKeys(part, {'cap', 'gap', 'labelFont'}, path);
        _choice(part, 'cap', KeyCapStyle.values, path);
        _number(part, 'gap', path, allowed: KeysStyle.gaps);
        _choice(part, 'labelFont', KeyLabelFont.values, path);
    }
  }

  void _choice<T extends Enum>(Map<String, dynamic> map, String key, List<T> values, List<String> path) {
    if (!map.containsKey(key)) return;
    if (values.asNameMap().containsKey(map[key])) return;
    _error([...path, key], '"$key" must be one of: ${values.map((e) => e.name).join(', ')}.');
  }

  void _bool(Map<String, dynamic> map, String key, List<String> path) {
    if (map.containsKey(key) && map[key] is! bool) _error([...path, key], '"$key" must be true or false.');
  }

  void _number(Map<String, dynamic> map, String key, List<String> path, {List<double>? allowed, double? max}) {
    if (!map.containsKey(key)) return;
    final v = map[key];
    final ok = v is num && (allowed == null || allowed.contains(v.toDouble())) && (max == null || (v >= 0 && v <= max));
    if (ok) return;
    final what = allowed != null ? 'one of: ${allowed.map((a) => a == a.roundToDouble() ? '${a.round()}' : '$a').join(', ')}' : 'a number from 0 to $max';
    _error([...path, key], '"$key" must be $what.');
  }
}
