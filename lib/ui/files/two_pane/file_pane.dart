import 'package:flutter/foundation.dart';

import '../../../sessions/session_manager.dart';
import '../../../src/rust/api/sftp.dart';
import '../../../src/rust/api/sftp_types.dart';
import '../../../src/rust/api/transfer.dart';
import '../file_format.dart';
import '../remote_paths.dart';
import 'phone_storage.dart';

/// What a pane shows: a folder on this phone, or a server.
sealed class PaneSource {
  const PaneSource();

  /// Short name for buttons and messages: "App files", "web-1".
  String get label;
}

class PhoneSource extends PaneSource {
  const PhoneSource(this.root);

  final PhoneRoot root;

  @override
  String get label => root.label;
}

class ServerSource extends PaneSource {
  const ServerSource(this.session);

  final LiveSession session;

  @override
  String get label => session.host.title;
}

/// One side of the two-pane copy screen: where it is, what is in the
/// folder, and which entries are ticked for copying.
class FilePane extends ChangeNotifier {
  FilePane({FileSide Function()? phoneSide, FileSide Function(RemoteFiles files)? serverSide})
    : _phoneSide = phoneSide ?? FileSide.phone,
      _serverSide = serverSide ?? ((files) => FileSide.server(files: files));

  final FileSide Function() _phoneSide;
  final FileSide Function(RemoteFiles files) _serverSide;

  PaneSource? _source;
  FileSide? _side;
  String _root = '/';
  String _path = '';
  List<RemoteEntry> _entries = const [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _showHidden = false;
  String? _error;
  int _request = 0;
  bool _disposed = false;

  PaneSource? get source => _source;

  /// The open side; only use it once [source] is set.
  FileSide get side => _side!;
  bool get ready => _side != null && _error == null;
  String get path => _path;
  bool get loading => _loading;
  bool get showHidden => _showHidden;

  /// Why the folder could not be listed.
  String? get error => _error;

  bool get canGoUp => _side != null && _path != _root && side.parent(path: _path) != _path;

  List<RemoteEntry> get entries => _showHidden ? _entries : _entries.where((e) => !RemotePaths.isHidden(e.name)).toList();

  /// Every entry, hidden ones included: for checking name clashes.
  List<RemoteEntry> get allEntries => _entries;

  List<RemoteEntry> get selected => _entries.where((e) => _selected.contains(e.path)).toList();
  bool isSelected(RemoteEntry entry) => _selected.contains(entry.path);

  /// Shows a folder on this phone, starting at [root].
  Future<void> showPhone(PhoneRoot root) async {
    _source = PhoneSource(root);
    _side = _phoneSide();
    _root = root.path;
    _path = '';
    _entries = const [];
    await open(root.path);
  }

  /// Shows a server's files, starting in the user's home folder.
  Future<void> showServer(LiveSession session, RemoteFiles files) async {
    _source = ServerSource(session);
    _side = _serverSide(files);
    _root = '/';
    _path = '';
    _entries = const [];
    try {
      final home = await files.home();
      await open(home);
    } catch (error) {
      _error = FileErrors.message(error);
      _notify();
    }
  }

  /// Lists [dir] and makes it the open folder. Ticks are cleared, since
  /// they belong to the folder that was open. Returns what went wrong, or
  /// null; on failure the old folder stays.
  Future<String?> open(String dir) async {
    final side = _side;
    if (side == null) return null;
    final request = ++_request;
    _loading = true;
    _notify();
    try {
      final entries = await side.list(dir: dir);
      if (request != _request) return null;
      _path = dir;
      _entries = entries;
      _selected.clear();
      _error = null;
      return null;
    } catch (error) {
      if (request != _request) return null;
      final message = FileErrors.message(error);
      // A failed first listing leaves nothing to show; later ones keep the old folder.
      if (_path.isEmpty || _path == dir) _error = message;
      return message;
    } finally {
      if (request == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<String?> refresh() => open(_path);

  Future<String?> up() => open(side.parent(path: _path));

  void toggle(RemoteEntry entry) {
    if (!_selected.remove(entry.path)) _selected.add(entry.path);
    _notify();
  }

  void selectAll() {
    _selected.addAll(entries.map((e) => e.path));
    _notify();
  }

  void clearSelection() {
    _selected.clear();
    _notify();
  }

  void toggleHidden() {
    _showHidden = !_showHidden;
    if (!_showHidden) {
      for (final entry in _entries) {
        if (RemotePaths.isHidden(entry.name)) _selected.remove(entry.path);
      }
    }
    _notify();
  }

  RemoteEntry? entryNamed(String name) => _entries.where((e) => e.name == name).firstOrNull;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
