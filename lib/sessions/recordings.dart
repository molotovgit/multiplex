import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A saved terminal recording.
class Recording {
  const Recording(this.file, this.savedAt, this.bytes);

  final File file;
  final DateTime savedAt;
  final int bytes;

  String get name => file.uri.pathSegments.last;

  /// "web 2026-11-06 14.05" from "web-20261106-140512.cast".
  String get label {
    final base = name.endsWith('.cast') ? name.substring(0, name.length - 5) : name;
    final m = RegExp(r'^(.*)-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\d{2}$').firstMatch(base);
    if (m == null) return base;
    return '${m[1]} ${m[2]}-${m[3]}-${m[4]} ${m[5]}.${m[6]}';
  }
}

/// The folder in app storage that keeps recordings (.cast files).
class RecordingLibrary {
  RecordingLibrary({Future<Directory> Function()? root}) : _root = root ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _root;

  Future<Directory> folder() async {
    final dir = Directory('${(await _root()).path}${Platform.pathSeparator}recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// A new file path for a recording of [title], named by time.
  Future<String> newPath(String title, {DateTime? at}) async {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return '${(await folder()).path}${Platform.pathSeparator}${slug.isEmpty ? 'terminal' : slug}-$stamp.cast';
  }

  /// All recordings, newest first.
  Future<List<Recording>> list() async {
    final dir = await folder();
    final out = <Recording>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.cast')) continue;
      final stat = await entry.stat();
      out.add(Recording(entry, stat.modified, stat.size));
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  Future<void> delete(Recording recording) async {
    if (await recording.file.exists()) await recording.file.delete();
  }
}
