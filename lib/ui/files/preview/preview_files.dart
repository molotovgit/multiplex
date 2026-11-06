import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../src/rust/api/sftp.dart';
import '../../../src/rust/api/sftp_types.dart';
import '../transfer_tasks.dart';

/// What a server file can be previewed as, if anything.
enum PreviewKind {
  image,
  pdf;

  static const _images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  /// Pictures bigger than this are offered as a download instead: a phone
  /// can run out of memory decoding them.
  static const maxImageBytes = 40 * 1024 * 1024;
  static const maxPdfBytes = 150 * 1024 * 1024;

  int get maxBytes => this == image ? maxImageBytes : maxPdfBytes;

  static PreviewKind? of(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    if (_images.contains(ext)) return image;
    if (ext == 'pdf') return pdf;
    return null;
  }
}

/// Temporary copies of server files, made only to show them. They live
/// in their own folder in the app's temporary space and are deleted when
/// the preview closes; anything left behind (the app was killed) goes the
/// next time a preview opens.
class PreviewFiles {
  PreviewFiles({Future<Directory> Function()? temp}) : _temp = temp ?? tempFolder;

  final Future<Directory> Function() _temp;

  /// Where temporary files go; tests point it at a folder of their own.
  static Future<Directory> Function() tempFolder = getTemporaryDirectory;

  static const folder = 'previews';

  /// Left-over copies older than this are deleted; a younger one may
  /// belong to a preview that is still open.
  static const staleAfter = Duration(hours: 1);

  Future<Directory> _dir() async {
    final temp = await _temp();
    final dir = Directory(LocalNames.join(temp.path, folder, separator: Platform.pathSeparator));
    await dir.create(recursive: true);
    return dir;
  }

  /// Downloads [entry] into the preview folder and returns the copy.
  Future<File> fetch(RemoteFiles files, RemoteEntry entry, FileTransfer transfer) async {
    final dir = await _dir();
    await _sweep(dir);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final local = File(LocalNames.join(dir.path, '$stamp-${LocalNames.safe(entry.name, windows: Platform.isWindows)}', separator: Platform.pathSeparator));
    await files.download(remotePath: entry.path, localPath: local.path, transfer: transfer);
    return local;
  }

  /// Deletes one copy. Never throws: the system clears temporary files anyway.
  static Future<void> discard(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Nothing more to do.
    }
  }

  Future<void> _sweep(Directory dir) async {
    final now = DateTime.now();
    try {
      await for (final item in dir.list()) {
        if (item is! File) continue;
        final changed = await item.lastModified();
        if (now.difference(changed) > staleAfter) await discard(item);
      }
    } on FileSystemException {
      // A copy that cannot be listed or deleted is left for the system.
    }
  }
}
