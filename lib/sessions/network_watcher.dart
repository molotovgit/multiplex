import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'session_manager.dart';

/// Tells the sessions when to check their connections: when the phone
/// reports that a network is back (Wi-Fi and mobile data swapped, or the
/// signal returned), and when the app comes back to the front after the
/// phone slept.
class NetworkWatcher with WidgetsBindingObserver {
  NetworkWatcher(this._sessions) {
    _channel.setMethodCallHandler(_onCall);
    WidgetsBinding.instance.addObserver(this);
  }

  static const _channel = MethodChannel('multiplex/network');

  final SessionManager _sessions;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'networkAvailable') await _sessions.networkBack();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sessions.checkConnections();
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
  }
}
