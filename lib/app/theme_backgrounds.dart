import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/vault_store.dart';
import 'theme_style.dart';

/// Something is wrong with a picture. The message is written for the user.
class BackgroundFileException implements Exception {
  const BackgroundFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Tells a picture by its first bytes, whatever its file name says, so a
/// renamed file or a web page saved as ".jpg" is never stored.
abstract final class PictureKind {
  static const extensions = ['png', 'jpg', 'jpeg', 'webp'];

  /// "png", "jpg" or "webp", or null when the bytes are not a picture
  /// Multiplex shows.
  static String? of(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'png';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'jpg';
    final riff = String.fromCharCodes(bytes.sublist(0, 4)), webp = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff == 'RIFF' && webp == 'WEBP') return 'webp';
    return null;
  }

  static bool hasPictureExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 && extensions.contains(fileName.substring(dot + 1).toLowerCase());
  }
}

/// A theme's background pictures, like the wallpapers of an Omarchy theme
/// pack. Each theme has its own folder in the app's support folder, named
/// after the theme's id; the theme lists the file names in order.
abstract final class ThemeBackgrounds {
  /// Big photos are fine, whole albums are not.
  static const maxBytes = 8 * 1024 * 1024;

  /// Tests keep pictures here instead of the real support folder.
  @visibleForTesting
  static Directory? rootOverride;

  static Future<Directory>? _root;

  static Future<Directory> root() {
    final override = rootOverride;
    if (override != null) return Future.value(override);
    return _root ??= () async {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}${Platform.pathSeparator}backgrounds');
    }();
  }

  /// The folder of one theme. Theme ids come from saved data, so an id
  /// that is not a plain name gets no folder at all.
  static Future<Directory?> folderFor(String themeId, {bool create = false}) async {
    if (SafeFileName.of(themeId) != themeId) return null;
    final dir = Directory('${(await root()).path}${Platform.pathSeparator}$themeId');
    if (create && !dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// The picture's file, or null when it is not on this device.
  static Future<File?> fileFor(String themeId, String name) async {
    try {
      final dir = await folderFor(themeId);
      if (dir == null || SafeFileName.of(name) != name) return null;
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      return file.existsSync() ? file : null;
    } catch (_) {
      // No support folder (tests, unusual platforms): no picture.
      return null;
    }
  }

  /// The names of the pictures in a theme's folder, sorted.
  static Future<List<String>> list(String themeId) async {
    final dir = await folderFor(themeId);
    if (dir == null || !dir.existsSync()) return const [];
    final names = [
      for (final entry in dir.listSync())
        if (entry is File) entry.uri.pathSegments.last,
    ]..sort();
    return names;
  }

  /// Keeps a picture in the theme's folder under a new name and returns
  /// that name. Refuses anything that is not a PNG, JPEG or WebP picture.
  static Future<String> addBytes(String themeId, Uint8List bytes, {String? sourceName}) async {
    final what = sourceName == null ? 'This file' : '"$sourceName"';
    if (bytes.length > maxBytes) throw BackgroundFileException('$what is larger than 8 MB. Pick a smaller picture.');
    final kind = PictureKind.of(bytes);
    if (kind == null) throw BackgroundFileException('$what is not a picture Multiplex can show. Pick a PNG, JPEG or WebP file.');
    final dir = await folderFor(themeId, create: true);
    if (dir == null) throw const BackgroundFileException('This theme cannot keep pictures. Save it as your own theme first.');
    final name = '${VaultStore.newId()}.$kind';
    await File('${dir.path}${Platform.pathSeparator}$name').writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Lets the user pick pictures and keeps copies. Returns the new names,
  /// empty when the user cancels.
  static Future<List<String>> pick(String themeId) async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Add background pictures', type: FileType.image);
    final names = <String>[];
    for (final file in picked) {
      final size = file.lengthSync() ?? await file.length();
      if (size != null && size > maxBytes) throw BackgroundFileException('"${file.name}" is larger than 8 MB. Pick a smaller picture.');
      names.add(await addBytes(themeId, await file.readAsBytes(), sourceName: file.name));
    }
    return names;
  }

  /// Copies pictures to another theme's folder, for a copy of a theme.
  static Future<void> copy(String fromId, String toId, List<String> names) async {
    if (names.isEmpty || fromId == toId) return;
    final to = await folderFor(toId, create: true);
    if (to == null) return;
    for (final name in names) {
      final file = await fileFor(fromId, name);
      await file?.copy('${to.path}${Platform.pathSeparator}$name');
    }
  }

  /// Deletes the pictures in a theme's folder that it no longer lists.
  static Future<void> keepOnly(String themeId, List<String> names) async {
    final dir = await folderFor(themeId);
    if (dir == null || !dir.existsSync()) return;
    for (final entry in dir.listSync()) {
      if (entry is File && !names.contains(entry.uri.pathSegments.last)) await _deleteQuietly(entry);
    }
  }

  /// Deletes a theme's whole folder, when the theme is deleted.
  static Future<void> deleteFolder(String themeId) async {
    final dir = await folderFor(themeId);
    try {
      if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException {
      // A leftover folder does no harm.
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // A leftover file does no harm.
    }
  }
}
