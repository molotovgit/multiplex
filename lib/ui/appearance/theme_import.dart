import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show AnyhowException;

import '../../app/theme_spec.dart';
import '../../data/vault_store.dart';
import '../../src/rust/api/theme.dart';
import '../../src/rust/api/theme_types.dart';
import 'color_tools.dart';

/// Something is wrong with a theme the user tried to bring in. The
/// message is written for the user: what went wrong and what to do.
class ThemeImportException implements Exception {
  const ThemeImportException(this.message);

  final String message;

  static const tooBig = ThemeImportException('This is larger than 1 MB, which is too big for a theme. Pick the theme file itself.');
  static const notText = ThemeImportException('This is not a text file. Pick a theme file, such as a .toml, .conf or .json file.');

  @override
  String toString() => message;
}

/// Reads theme text into a [ThemeSpec]. Understands VaultTerm's own JSON
/// and, through the Rust core, Alacritty (.toml), Kitty (.conf) and
/// Ghostty theme files.
class ThemeImporter {
  /// [parse] reads non-JSON text; tests pass their own.
  ThemeImporter({ImportedTheme Function(String text)? parse}) : _parse = parse ?? _parseWithCore;

  final ImportedTheme Function(String text) _parse;

  /// The most a theme may weigh. Real theme files are a few kilobytes.
  static const maxBytes = 1024 * 1024;

  /// Used when neither the theme nor its source has a name.
  static const fallbackName = 'Imported theme';

  static ImportedTheme _parseWithCore(String text) => parseThemeFile(text: text);

  /// Turns file or download bytes into text. Refuses anything that is not
  /// UTF-8 text, such as a picture or a font picked by mistake.
  static String decode(List<int> bytes) {
    if (bytes.length > maxBytes) throw ThemeImportException.tooBig;
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw ThemeImportException.notText;
    }
    if (text.contains('\u0000')) throw ThemeImportException.notText;
    // Some editors put an invisible marker at the start; drop it.
    return text.startsWith('﻿') ? text.substring(1) : text;
  }

  /// Reads [text] into a new theme with a fresh id. [sourceName] is the
  /// readable name of the file or link it came from, used when the theme
  /// itself has no name.
  ThemeSpec read(String text, {String? sourceName}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const ThemeImportException('There is no text to import. Paste or pick a theme first.');
    final fallback = (sourceName == null || sourceName.trim().isEmpty) ? fallbackName : sourceName.trim();
    return trimmed.startsWith('{') ? _fromJson(trimmed, fallback) : _fromThemeFile(trimmed, fallback);
  }

  /// The accent is the theme's blue, unless the blue barely shows on the
  /// background; then the cursor colour is used instead.
  static int pickAccent({required List<int> ansi, required int cursor, required int background}) {
    final blue = ansi[4];
    return ColorContrast.ratio(blue, background) >= ColorContrast.lowAccent ? blue : cursor;
  }

  ThemeSpec _fromJson(String text, String fallback) {
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      throw const ThemeImportException(
        'This looks like a VaultTerm theme, but the JSON could not be read. Check that all of it was copied.',
      );
    }
    if (data is! Map<String, dynamic> || data['foreground'] is! num || data['background'] is! num) {
      throw const ThemeImportException(
        'This JSON is not a VaultTerm theme. Export a theme from VaultTerm and import that.',
      );
    }
    final spec = ThemeSpec.fromJson(data);
    final name = data['name'] is String && (data['name'] as String).trim().isNotEmpty ? spec.name.trim() : fallback;
    final accent = data['accent'] is num ? spec.accent : pickAccent(ansi: spec.ansi, cursor: spec.cursor, background: spec.background);
    return spec.copyWith(id: VaultStore.newId(), name: name, accent: accent);
  }

  ThemeSpec _fromThemeFile(String text, String fallback) {
    final ImportedTheme imported;
    try {
      imported = _parse(text);
    } on AnyhowException catch (e) {
      throw ThemeImportException(
        '${_sentence(e.message)} VaultTerm can import Alacritty, Kitty and Ghostty themes and its own exported themes.',
      );
    }
    final opaque = [for (final c in imported.ansi) 0xFF000000 | c];
    if (opaque.length != 16) {
      throw const ThemeImportException('This theme does not have all 16 terminal colours. Pick a complete theme file.');
    }
    final foreground = 0xFF000000 | imported.foreground;
    final background = 0xFF000000 | imported.background;
    final cursor = imported.cursor == null ? foreground : 0xFF000000 | imported.cursor!;
    final ownName = imported.name?.trim();
    return ThemeSpec(
      id: VaultStore.newId(),
      name: (ownName == null || ownName.isEmpty) ? fallback : ownName,
      ansi: opaque,
      foreground: foreground,
      background: background,
      cursor: cursor,
      accent: pickAccent(ansi: opaque, cursor: cursor, background: background),
      selection: imported.selection == null ? null : 0xFF000000 | imported.selection!,
    );
  }

  /// "the theme has no background colour" -> "The theme has no background colour."
  static String _sentence(String message) {
    final text = message.trim();
    if (text.isEmpty) return 'This theme could not be read.';
    final capital = text[0].toUpperCase() + text.substring(1);
    return capital.endsWith('.') ? capital : '$capital.';
  }
}

/// Makes a readable theme name from where the theme came from.
abstract final class ThemeSourceName {
  /// "tokyo-night.toml" -> "Tokyo Night"; "/x/catppuccin_mocha.conf" ->
  /// "Catppuccin Mocha". Null when nothing readable is left.
  static String? fromFileName(String fileName) {
    var base = fileName.split(RegExp(r'[\\/]')).last.trim();
    final dot = base.lastIndexOf('.');
    if (dot > 0 && base.length - dot <= 6) base = base.substring(0, dot);
    final words = base.split(RegExp(r'[\s_\-.]+')).where((w) => w.isNotEmpty);
    final name = words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
    return name.isEmpty ? null : name;
  }

  /// The name of the file a link points to.
  static String? fromUrl(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? null : fromFileName(segments.last);
  }
}
