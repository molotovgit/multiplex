import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A file waiting on the phone for a computer that could not be reached.
class WaitingFile {
  const WaitingFile({required this.name, required this.path});

  final String name;
  final String path;
}

/// Files shared to a paired computer while it was out of reach. They wait
/// in the app's own storage, a folder per computer, and go as soon as the
/// phone is next connected to it.
class PhoneOutbox {
  PhoneOutbox({Future<Directory> Function()? root}) : _root = root ?? _appFolder;

  final Future<Directory> Function() _root;

  static Future<Directory> _appFolder() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}outbox');
  }

  Future<Directory> _folder(String hostId) async {
    // Host ids are made by the app (letters, digits, dashes); anything
    // else is kept out of the path all the same.
    final safe = hostId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dir = Directory('${(await _root()).path}${Platform.pathSeparator}$safe');
    await dir.create(recursive: true);
    return dir;
  }

  /// Keeps a file for later. It is moved here (shared files start in a
  /// cache Android may clear); with a name already waiting, it gets a
  /// number.
  Future<WaitingFile> add(String hostId, {required String name, required String path}) async {
    final dir = await _folder(hostId);
    var target = File('${dir.path}${Platform.pathSeparator}$name');
    final dot = name.lastIndexOf('.');
    final (base, ext) = dot > 0 ? (name.substring(0, dot), name.substring(dot)) : (name, '');
    for (var n = 1; await target.exists(); n++) {
      target = File('${dir.path}${Platform.pathSeparator}$base ($n)$ext');
    }
    final source = File(path);
    try {
      await source.rename(target.path);
    } on FileSystemException {
      // Another storage volume: copy, then drop the original.
      await source.copy(target.path);
      await source.delete();
    }
    return WaitingFile(name: target.uri.pathSegments.last, path: target.path);
  }

  /// What waits for a computer, oldest first.
  Future<List<WaitingFile>> waiting(String hostId) async {
    final dir = await _folder(hostId);
    final files = [
      await for (final e in dir.list())
        if (e is File) e,
    ];
    final times = {for (final f in files) f.path: (await f.stat()).modified};
    files.sort((a, b) {
      final byTime = times[a.path]!.compareTo(times[b.path]!);
      return byTime != 0 ? byTime : a.path.compareTo(b.path);
    });
    return [for (final f in files) WaitingFile(name: f.uri.pathSegments.last, path: f.path)];
  }

  /// It has been sent (or is not wanted any more).
  Future<void> remove(WaitingFile file) async {
    try {
      await File(file.path).delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
