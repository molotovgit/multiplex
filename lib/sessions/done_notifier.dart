import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/vault_store.dart';
import 'command_timer.dart';

/// Shows a notification when a long command finishes while the user is
/// not looking at its terminal: "Done on web: npm run build (1m 12s)".
class DoneNotifier {
  DoneNotifier(this._store, {Future<void> Function(String title, String body)? post, bool Function()? appInFront})
      : _post = post ?? _postOnPhone,
        _appInFront = appInFront ?? _isResumed;

  /// Commands shorter than this are not worth a notification.
  static const minimum = Duration(seconds: 10);

  static const _channel = MethodChannel('multiplex/sessions');

  final VaultStore _store;
  final Future<void> Function(String title, String body) _post;
  final bool Function() _appInFront;

  /// Notifies about [done] on [hostTitle] when it ran long enough, the
  /// setting is on and its terminal is not on screen. Returns whether it
  /// did.
  bool finished(String hostTitle, FinishedCommand done, {required bool terminalOnScreen}) {
    if (!_store.settings.notifyWhenDone || done.took < minimum) return false;
    if (terminalOnScreen && _appInFront()) return false;
    final (title, body) = text(hostTitle, done);
    _post(title, body);
    return true;
  }

  /// The notification's title and text.
  static (String, String) text(String hostTitle, FinishedCommand done) {
    final failed = done.exitCode != null && done.exitCode != 0;
    final command = done.command.isEmpty ? 'A command' : done.command;
    final title = failed ? 'Failed on $hostTitle' : 'Done on $hostTitle';
    final code = failed ? ', exit code ${done.exitCode}' : '';
    return (title, '$command (${took(done.took)}$code)');
  }

  /// "42s", "1m 12s", "2h 5m".
  static String took(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  static bool _isResumed() => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  static Future<void> _postOnPhone(String title, String body) async {
    try {
      await _channel.invokeMethod<void>('notifyDone', {'title': title, 'body': body});
    } on MissingPluginException {
      // Desktop and iOS builds have no handler.
    } on PlatformException {
      // A notification is never worth an error.
    }
  }
}
