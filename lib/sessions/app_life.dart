import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/vault_store.dart';
import 'session_manager.dart';

/// The app without its screen.
///
/// On Android the app's engine outlives the screen: it keeps running when
/// the app is swiped away, and can be started with the phone before the
/// app has been opened. This decides what that is for. Paired computers
/// set to stay connected keep their link; everything that was only there
/// for the screen (a terminal on some server, a remote desktop, a
/// picture being sent) is closed when the app is swiped away, as before.
class AppLife {
  AppLife(this._sessions, this._store, {MethodChannel channel = const MethodChannel('multiplex/life'), this.closeScreens})
    // ignore: prefer_initializing_formals
    : _channel = channel {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'taskRemoved') await taskRemoved();
    });
    _store.addListener(_sync);
    _sync();
  }

  final SessionManager _sessions;
  final VaultStore _store;
  final MethodChannel _channel;

  /// Leaves every screen but the first, and stops what a screen started
  /// (showing the phone's screen, its camera, its microphone, the speaker).
  final void Function()? closeScreens;

  bool? _told;

  /// Whether this computer keeps its link when the app has no screen.
  static bool keeps(Host host) => host.computer && host.stayConnected;

  /// The app was swiped away.
  Future<void> taskRemoved() async {
    closeScreens?.call();
    var closed = 0;
    for (final session in _sessions.sessions.toList()) {
      if (keeps(session.host)) continue;
      await _sessions.disconnect(session);
      closed++;
    }
    if (kDebugMode) debugPrint('mpxlife swiped away: closed $closed, kept ${_sessions.sessions.length}');
  }

  /// Tells Android whether there is anything to start with the phone for.
  void _sync() {
    final wanted = _store.hosts.any(keeps);
    if (wanted == _told) return;
    _told = wanted;
    unawaited(_tell(wanted));
  }

  Future<void> _tell(bool wanted) async {
    try {
      await _channel.invokeMethod<void>('setLinks', wanted);
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // It is asked again the next time the computers change.
    }
  }

  void dispose() {
    _store.removeListener(_sync);
    _channel.setMethodCallHandler(null);
  }
}
