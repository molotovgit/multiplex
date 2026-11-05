import 'dart:convert';
import 'dart:typed_data';

import '../../app/theme_backgrounds.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';
import 'theme_import.dart';

/// A theme and its background pictures in one file: Multiplex's theme
/// JSON plus the pictures as base64 text. Import reads it back into a new
/// theme with its own copies of the pictures.
abstract final class ThemePackFile {
  /// Written first in the file, so a pack is told apart at a glance.
  static const format = 'multiplex-theme-pack';
  static const version = 1;

  /// The pictures together may weigh this much. Base64 adds a third, so
  /// a file stays under about 34 MB.
  static const maxPictureBytes = 25 * 1024 * 1024;

  /// The most a pack file may weigh when it is read back.
  static const maxFileBytes = maxPictureBytes * 4 ~/ 3 + 2 * 1024 * 1024;

  static const tooBig = ThemeImportException('The pictures of this theme come to more than 25 MB. Remove a few, then export again.');

  /// True when [text] starts like a pack file.
  static bool isPack(String text) {
    final head = text.length > 200 ? text.substring(0, 200) : text;
    return head.contains('"format"') && head.contains(format);
  }

  /// The pack for [theme], with every picture still on this device.
  static Future<String> write(ThemeSpec theme) async {
    final pictures = <Map<String, String>>[];
    var total = 0;
    for (final name in theme.backgrounds) {
      final file = await ThemeBackgrounds.fileFor(theme.id, name);
      if (file == null) continue;
      final bytes = await file.readAsBytes();
      total += bytes.length;
      if (total > maxPictureBytes) throw tooBig;
      pictures.add({'name': name, 'data': base64Encode(bytes)});
    }
    final kept = {for (final p in pictures) p['name']};
    final json = {
      'format': format,
      'version': version,
      'theme': theme.copyWith(
        backgrounds: [for (final n in theme.backgrounds) if (kept.contains(n)) n],
        activeBackground: kept.length == theme.backgrounds.length ? theme.activeBackground : 0,
      ).toJson(),
      'pictures': pictures,
    };
    return jsonEncode(json);
  }

  /// Reads a pack into a new theme. Its pictures are checked and kept in
  /// the new theme's folder; the theme itself is not saved yet.
  static Future<ThemeSpec> read(String text, ThemeImporter importer) async {
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      throw const ThemeImportException('This theme file is damaged and could not be read. Export the theme again.');
    }
    if (data is! Map || data['format'] != format || data['theme'] is! Map) {
      throw const ThemeImportException('This is not a Multiplex theme with pictures. Export the theme again.');
    }
    if (data['version'] is! int || (data['version'] as int) > version) {
      throw const ThemeImportException('This theme was saved by a newer Multiplex. Update the app, then import it again.');
    }
    final spec = importer.read(jsonEncode(data['theme']));
    final wanted = [
      if ((data['theme'] as Map)['backgrounds'] is List)
        for (final n in (data['theme'] as Map)['backgrounds'] as List) ?SafeFileName.of(n),
    ];
    final byName = <String, Uint8List>{};
    var total = 0;
    for (final entry in data['pictures'] is List ? data['pictures'] as List : const []) {
      if (entry is! Map || entry['name'] is! String || entry['data'] is! String) continue;
      final Uint8List bytes;
      try {
        bytes = base64Decode(entry['data'] as String);
      } on FormatException {
        continue;
      }
      total += bytes.length;
      if (total > maxPictureBytes) throw tooBig;
      byName[entry['name'] as String] = bytes;
    }
    final names = <String>[];
    for (final name in wanted) {
      final bytes = byName[name];
      // Damaged or missing pictures are left out; the rest still come in.
      if (bytes == null || PictureKind.of(bytes) == null) continue;
      names.add(await ThemeBackgrounds.addBytes(spec.id, bytes, sourceName: name));
    }
    final active = (data['theme'] as Map)['activeBackground'];
    final steps = spec.backdrops.length + names.length;
    return spec.copyWith(backgrounds: names, activeBackground: active is int && active >= 0 && active <= steps ? active : 0);
  }
}
