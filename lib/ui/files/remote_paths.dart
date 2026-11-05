/// One step of a folder path, for the tappable path bar.
class PathSegment {
  const PathSegment(this.label, this.path);

  /// What the user sees, for example "logs" (or "/" for the top folder).
  final String label;

  /// The full path this step opens, for example "/var/logs".
  final String path;
}

/// Path rules for the server, which always uses "/" no matter which
/// device the app runs on. These match the Rust core's `RemotePath`, but
/// live in Dart so the screens can work them out without a round trip
/// (and so they can be tested without the native library).
abstract final class RemotePaths {
  /// `dir` + "/" + `name`.
  static String join(String dir, String name) {
    if (dir.isEmpty || dir == '.') return name;
    if (dir.endsWith('/')) return '$dir$name';
    return '$dir/$name';
  }

  /// The folder that holds `path` ("/" for top-level entries).
  static String parent(String path) {
    var trimmed = path;
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final slash = trimmed.lastIndexOf('/');
    if (slash == 0) return '/';
    if (slash < 0) return '.';
    return trimmed.substring(0, slash);
  }

  /// The last part of a path: "/var/log/syslog" gives "syslog".
  static String name(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty);
    return parts.isEmpty ? '/' : parts.last;
  }

  /// The steps of a path, from the top folder down:
  /// "/home/ann" gives "/", "home", "ann".
  static List<PathSegment> segments(String path) {
    final absolute = path.startsWith('/');
    final result = <PathSegment>[if (absolute) const PathSegment('/', '/')];
    var current = absolute ? '/' : '';
    for (final part in path.split('/')) {
      if (part.isEmpty) continue;
      current = current.isEmpty ? part : join(current, part);
      result.add(PathSegment(part, current));
    }
    if (result.isEmpty) result.add(PathSegment(path, path));
    return result;
  }

  /// Turns what the user typed into a path the server understands:
  /// "~" and "~/..." start in the home folder, other relative paths start
  /// in the current folder. The server then resolves ".." and links.
  static String resolve(String typed, {required String current, required String home}) {
    final text = typed.trim();
    if (text.isEmpty) return current;
    if (text == '~') return home;
    if (text.startsWith('~/')) return join(home, text.substring(2));
    if (text.startsWith('/')) return text;
    return join(current, text);
  }

  /// Names that start with a dot are hidden by convention.
  static bool isHidden(String name) => name.startsWith('.');

  /// Says what is wrong with a new file or folder name, or null if it is fine.
  static String? nameProblem(String name) {
    if (name.trim().isEmpty) return 'Type a name.';
    if (name.contains('/')) return 'Names cannot contain "/".';
    if (name == '.' || name == '..') return 'Choose a name other than "." or "..".';
    if (name.contains('\u0000')) return 'Names cannot contain hidden control characters.';
    return null;
  }
}
