import 'package:flutter/services.dart';

import 'session_manager.dart';

/// Keeps connections alive while the app is in the background.
///
/// On Android it tells the app's foreground service how many connections
/// are open, so the system shows a small "connected" notification instead
/// of freezing the app. Other platforms ignore it.
class BackgroundKeeper {
  BackgroundKeeper(this._sessions) {
    _sessions.addListener(_update);
  }

  static const _channel = MethodChannel('multiplex/sessions');

  final SessionManager _sessions;

  /// The last state sent, so the platform is only told about changes (the
  /// session manager also ticks every two seconds).
  String? _lastSent;

  void _update() {
    // A connection being restored still needs the app kept running.
    final open = _sessions.sessions.where((s) => s.connected || s.reconnecting).toList();
    final summary = open.map((s) => s.host.title).join(', ');
    final state = '${open.length}|$summary';
    if (state == _lastSent) return;
    _lastSent = state;
    _send(open.length, summary);
  }

  Future<void> _send(int count, String summary) async {
    try {
      await _channel.invokeMethod<void>('setOpenSessions', {'count': count, 'summary': summary});
    } on MissingPluginException {
      // Desktop and iOS builds have no handler.
    } on PlatformException {
      // Never let the notification break connecting.
    }
  }

  void dispose() => _sessions.removeListener(_update);
}
