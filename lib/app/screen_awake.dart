import 'package:flutter/services.dart';

/// Keeps the screen on while a terminal is open, so a long command stays
/// visible. Uses a small native call on Android; other platforms ignore it.
abstract final class ScreenAwake {
  static const _channel = MethodChannel('vaultterm/screen');

  /// How many open terminal screens want the screen on.
  static int _holders = 0;

  static Future<void> hold() async {
    _holders++;
    if (_holders == 1) await _set(true);
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _set(false);
  }

  static Future<void> _set(bool on) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'on': on});
    } on MissingPluginException {
      // Desktop and iOS builds have no handler: nothing to do.
    } on PlatformException {
      // Never let this nicety break the terminal.
    }
  }
}
