import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/vault_store.dart';

/// Something is wrong with a picture the user picked. The message is
/// written for the user.
class BackgroundFileException implements Exception {
  const BackgroundFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pictures behind the terminal. A picked file is copied into the app's
/// support folder under a name of its own; themes store only that name.
abstract final class TerminalBackgrounds {
  static const extensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

  /// Large photos are fine, but not whole albums.
  static const maxBytes = 20 * 1024 * 1024;

  /// Tests put pictures here instead of the real support folder.
  @visibleForTesting
  static Directory? folderOverride;

  static Future<Directory>? _folder;

  /// Folder that keeps the pictures, made on first use.
  static Future<Directory> folder() {
    final override = folderOverride;
    if (override != null) return Future.value(override);
    return _folder ??= () async {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}backgrounds');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }();
  }

  /// The picture's file, or null when it is not on this device (for
  /// example in a theme imported from another phone).
  static Future<File?> fileFor(String name) async {
    try {
      final file = File('${(await folder()).path}${Platform.pathSeparator}$name');
      return file.existsSync() ? file : null;
    } catch (_) {
      // No support folder (tests, unusual platforms): no picture.
      return null;
    }
  }

  /// Lets the user pick a picture and keeps a copy. Returns the stored
  /// file name, or null when the user cancels.
  static Future<String?> pick() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Pick a background picture', type: FileType.image);
    if (picked == null) return null;
    final extension = (picked.extension ?? '').toLowerCase();
    if (!extensions.contains(extension)) {
      throw BackgroundFileException('"${picked.name}" is not a picture Multiplex can show. Pick a PNG, JPEG, WebP or GIF file.');
    }
    final size = picked.lengthSync() ?? await picked.length();
    if (size != null && size > maxBytes) {
      throw BackgroundFileException('"${picked.name}" is larger than 20 MB. Pick a smaller picture.');
    }
    final name = '${VaultStore.newId()}.$extension';
    final file = File('${(await folder()).path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(await picked.readAsBytes(), flush: true);
    return name;
  }

  /// Deletes a picture once no saved theme uses it any more.
  static Future<void> removeIfUnused(VaultStore store, String name) async {
    if (store.allThemes.any((t) => t.style.terminal.backgroundImage == name)) return;
    try {
      final file = await fileFor(name);
      if (file != null) await file.delete();
    } on FileSystemException {
      // A leftover file does no harm.
    }
  }
}
