import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/sftp.dart';
import '../../src/rust/api/sftp_types.dart';
import 'remote_paths.dart';
import 'transfer_queue.dart';

/// Picks names for files saved on this device: safe for the local file
/// system, and never on top of a file that is already there.
abstract final class LocalNames {
  static const _windowsBad = r'<>:"/\|?*';
  static const _windowsReserved = {'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'LPT1', 'LPT2', 'LPT3'};

  static String join(String dir, String name, {String separator = '/'}) =>
      dir.endsWith(separator) ? '$dir$name' : '$dir$separator$name';

  /// The part before the last dot: "notes" for "notes.txt". Dot files
  /// such as ".bashrc" count as all name, no extension.
  static String stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// ".txt" for "notes.txt", empty when there is none.
  static String extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }

  /// Replaces characters the local file system does not allow. Server
  /// names can hold ":" or "?", which Windows refuses.
  static String safe(String name, {required bool windows}) {
    var result = name.replaceAll('/', '_').replaceAll('\u0000', '_');
    if (windows) {
      final buffer = StringBuffer();
      for (final rune in result.runes) {
        final char = String.fromCharCode(rune);
        buffer.write(rune < 32 || _windowsBad.contains(char) ? '_' : char);
      }
      result = buffer.toString().replaceAll(RegExp(r'[. ]+$'), '');
      if (_windowsReserved.contains(stem(result).toUpperCase())) result = '_$result';
    }
    return result.isEmpty ? 'download' : result;
  }

  /// `name` if it is free in `dir`, otherwise "name (1).ext", "name (2).ext"...
  static String free(String dir, String name, {required bool Function(String path) exists, String separator = '/'}) {
    final first = join(dir, name, separator: separator);
    if (!exists(first)) return first;
    final base = stem(name);
    final ext = extension(name);
    for (var n = 1; ; n++) {
      final candidate = join(dir, '$base ($n)$ext', separator: separator);
      if (!exists(candidate)) return candidate;
    }
  }
}

/// The folder downloads land in.
abstract final class DownloadFolder {
  /// Made inside the app's documents on phones, which have no shared
  /// downloads folder the app can write to directly.
  static const subfolder = 'VaultTerm downloads';

  static Future<Directory> resolve() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) return downloads;
      } on UnsupportedError {
        // Falls through to the documents folder below.
      }
    }
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(LocalNames.join(documents.path, subfolder, separator: Platform.pathSeparator));
    await dir.create(recursive: true);
    return dir;
  }
}

/// A file the user picked to upload. Most pickers hand over a real path;
/// some (Android content links) only give a stream, so it is copied to a
/// temporary file first and that copy is deleted afterwards.
class UploadSource {
  UploadSource({required this.name, this.path, this.openStream});

  factory UploadSource.picked(PlatformFile file) => UploadSource(name: file.name, path: file.path, openStream: file.readAsByteStream);

  final String name;
  final String? path;
  final Stream<List<int>> Function()? openStream;
  File? _temporary;

  /// A local path the Rust core can read.
  Future<String> prepare() async {
    final direct = path;
    if (direct != null) return direct;
    final stream = openStream;
    if (stream == null) throw StateError('The picked file "$name" cannot be read on this device.');
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = File(LocalNames.join(temp.path, 'upload-$stamp-${LocalNames.safe(name, windows: Platform.isWindows)}', separator: Platform.pathSeparator));
    final sink = file.openWrite();
    await sink.addStream(stream());
    await sink.close();
    _temporary = file;
    return file.path;
  }

  /// Deletes the temporary copy, if one was made.
  Future<void> release() async {
    final temp = _temporary;
    _temporary = null;
    if (temp == null) return;
    try {
      await temp.delete();
    } on FileSystemException {
      // The system cleans its temporary folder anyway.
    }
  }
}

/// Uploads one local file into a server folder. An existing file with the
/// same name is replaced. The core writes to "name.part" first and
/// removes that itself on cancel or failure, so a stopped upload leaves
/// the old file as it was and nothing needs tidying here.
class UploadTask extends TransferTask {
  UploadTask({required this.files, required this.source, required this.remoteFolder});

  final RemoteFiles files;
  final UploadSource source;

  @override
  final String remoteFolder;

  String get remotePath => RemotePaths.join(remoteFolder, source.name);

  @override
  String get name => source.name;

  @override
  TransferDirection get direction => TransferDirection.upload;

  /// Two uploads to the same server file would share one ".part" file.
  @override
  String get exclusiveKey => 'upload:$remotePath';

  @override
  Future<String> run(FileTransfer transfer) async {
    try {
      final local = await source.prepare();
      await files.upload(localPath: local, remotePath: remotePath, transfer: transfer);
      return remotePath;
    } finally {
      await source.release();
    }
  }
}

/// Downloads one server file into the downloads folder.
class DownloadTask extends TransferTask {
  DownloadTask({required this.files, required this.entry, Future<Directory> Function()? folder}) : _folder = folder ?? DownloadFolder.resolve;

  final RemoteFiles files;
  final RemoteEntry entry;
  final Future<Directory> Function() _folder;

  String get _localName => LocalNames.safe(entry.name, windows: Platform.isWindows);

  @override
  String get name => entry.name;

  @override
  TransferDirection get direction => TransferDirection.download;

  @override
  String get remoteFolder => RemotePaths.parent(entry.path);

  /// Two downloads of the same name wait for each other, so the second
  /// sees the first one's file and picks "name (1)" instead of the same
  /// free name. Lower case, because Windows and macOS ignore case.
  @override
  String get exclusiveKey => 'download:${_localName.toLowerCase()}';

  @override
  Future<String> run(FileTransfer transfer) async {
    final dir = await _folder();
    // Picked when the download starts, not when it was queued, so the
    // name is still free when the file arrives.
    final local = LocalNames.free(dir.path, _localName, exists: (p) => File(p).existsSync(), separator: Platform.pathSeparator);
    await files.download(remotePath: entry.path, localPath: local, transfer: transfer);
    return local;
  }
}
