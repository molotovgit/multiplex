import 'dart:async';

import 'package:flutter/foundation.dart';

import 'server_stats.dart';

/// What the status card shows right now.
enum StatusPhase {
  /// The first reading is on its way.
  loading,

  /// [ServerStatusController.stats] holds the latest reading.
  ready,

  /// The server is not Linux, so there is nothing to read.
  unsupported,

  /// The last reading failed; see [ServerStatusController.error].
  failed,
}

/// Reads a server's CPU, memory, disk, load and uptime every few seconds,
/// while [running]. The command runs through [exec], which returns the
/// command's standard output (a separate SSH exec channel in the app).
class ServerStatusController extends ChangeNotifier {
  ServerStatusController(this._exec, {this.every = const Duration(seconds: 5), bool Function()? isVisible}) : _isVisible = isVisible ?? _always;

  final Future<String> Function(String command) _exec;
  final Duration every;

  /// Readings are skipped while this says no (another page covers the
  /// card), so nothing runs on the server that nobody looks at.
  final bool Function() _isVisible;

  static bool _always() => true;

  Timer? _timer;
  bool _reading = false;
  bool _disposed = false;
  StatusPhase _phase = StatusPhase.loading;
  ServerStats? _stats;
  String? _error;
  DateTime? _readAt;

  StatusPhase get phase => _phase;
  ServerStats? get stats => _stats;
  String? get error => _error;

  /// When the shown numbers were read.
  DateTime? get readAt => _readAt;
  bool get running => _timer != null;

  /// Reads now, then every [every]. Calling it again does nothing.
  void start() {
    if (_timer != null || _disposed) return;
    _timer = Timer.periodic(every, (_) => refresh());
    refresh();
  }

  /// Stops reading (the numbers stay on screen).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reads once. A reading still on its way is not started twice.
  Future<void> refresh() async {
    if (_reading || _disposed || !_isVisible()) return;
    _reading = true;
    try {
      final stats = ServerStats.parse(await _exec(ServerStats.command));
      if (_disposed) return;
      if (stats == null) {
        _phase = StatusPhase.unsupported;
        // Nothing will change on the next try.
        stop();
      } else {
        _stats = stats;
        _error = null;
        _readAt = DateTime.now();
        _phase = StatusPhase.ready;
      }
    } catch (error) {
      if (_disposed) return;
      _error = '$error';
      _phase = StatusPhase.failed;
    } finally {
      _reading = false;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
