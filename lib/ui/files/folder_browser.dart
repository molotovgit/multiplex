import 'package:flutter/foundation.dart';

import '../../sessions/session_manager.dart';
import '../../src/rust/api/sftp.dart';
import '../../src/rust/api/sftp_types.dart';
import 'file_format.dart';
import 'remote_paths.dart';

/// Where the file browser is in its start-up.
enum BrowserStatus { opening, ready, failed }

/// The state of the remote file browser: which folder is open, what is in
/// it, and whether hidden files show. Screens listen to it and redraw.
class FolderBrowser extends ChangeNotifier {
  /// [connect] opens the SFTP channel, usually `session.ssh.openFiles`.
  FolderBrowser(this._connect);

  final Future<RemoteFiles> Function() _connect;

  RemoteFiles? _files;
  BrowserStatus _status = BrowserStatus.opening;
  String? _openError;
  String _path = '';
  String _home = '';
  List<RemoteEntry> _entries = const [];
  bool _showHidden = false;
  bool _loading = false;
  int _busy = 0;
  bool _disposed = false;

  /// Counts folder requests, so a slow answer for a folder the user has
  /// already left never replaces the newer listing.
  int _request = 0;

  BrowserStatus get status => _status;

  /// Why the browser could not start, when [status] is failed.
  String? get openError => _openError;

  /// The SFTP channel. Only use it once [status] is ready.
  RemoteFiles get files => _files!;

  String get path => _path;
  String get home => _home;
  bool get showHidden => _showHidden;

  /// True while a folder is being listed or a change is on its way to the
  /// server (the old listing stays visible meanwhile).
  bool get loading => _loading || _busy > 0;

  /// Runs a server call with the progress bar showing, so the user sees
  /// that something is happening when the server is slow.
  Future<T> track<T>(Future<T> Function() call) async {
    _busy++;
    _notify();
    try {
      return await call();
    } finally {
      _busy--;
      _notify();
    }
  }

  bool get canGoUp => _path.isNotEmpty && _path != '/' && RemotePaths.parent(_path) != _path;

  /// The entries to show, without hidden ones unless they are switched on.
  List<RemoteEntry> get entries => _showHidden ? _entries : _entries.where((e) => !RemotePaths.isHidden(e.name)).toList();

  /// How many entries the hidden-files filter is leaving out.
  int get hiddenCount => _showHidden ? 0 : _entries.where((e) => RemotePaths.isHidden(e.name)).length;

  /// Opens the SFTP channel and lists the home folder, or the folder `at`
  /// (or the folder of the file `at`) when it can be opened.
  Future<void> start({String? at}) async {
    _status = BrowserStatus.opening;
    _openError = null;
    _notify();
    try {
      final files = _files ??= await _connect();
      final home = await files.home();
      final entries = await files.list(dir: home);
      _home = home;
      _path = home;
      _entries = entries;
      _status = BrowserStatus.ready;
    } catch (error) {
      _openError = FileErrors.message(error);
      _status = BrowserStatus.failed;
    }
    _notify();
    if (at != null && _status == BrowserStatus.ready && await goTo(at) != null) await goTo(RemotePaths.parent(at));
  }

  /// Lists `dir` and makes it the current folder. Returns what went wrong,
  /// or null on success. On failure the browser stays where it was.
  Future<String?> open(String dir) async {
    final request = ++_request;
    _loading = true;
    _notify();
    try {
      final entries = await files.list(dir: dir);
      if (request == _request) {
        _path = dir;
        _entries = entries;
      }
      return null;
    } catch (error) {
      return request == _request ? FileErrors.message(error) : null;
    } finally {
      if (request == _request) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<String?> refresh() => open(_path);

  Future<String?> up() => open(RemotePaths.parent(_path));

  /// Opens a folder the user typed: "~/logs", "../etc", "/var/www".
  Future<String?> goTo(String typed) async {
    final target = RemotePaths.resolve(typed, current: _path, home: _home);
    try {
      final real = await files.canonicalize(path: target);
      return await open(real);
    } catch (error) {
      return FileErrors.message(error);
    }
  }

  void toggleHidden() {
    _showHidden = !_showHidden;
    _notify();
  }

  /// The entry called `name` in the current folder, hidden ones included.
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

/// Tells the screen when the connection drops. The session manager
/// re-checks every couple of seconds; this only passes on actual changes,
/// so the file list does not redraw for nothing.
class ConnectionWatch extends ValueNotifier<bool> {
  ConnectionWatch(this._session, this._ticks) : super(_session.connected) {
    _ticks.addListener(check);
  }

  final LiveSession _session;
  final Listenable _ticks;

  /// Looks again right now, for example after an action failed.
  void check() => value = _session.connected;

  @override
  void dispose() {
    _ticks.removeListener(check);
    super.dispose();
  }
}
