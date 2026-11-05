import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../../sessions/connect_flow.dart';
import '../../sessions/session_manager.dart';
import '../common/dialog_prompter.dart';
import '../terminal/terminal_screen.dart';

/// Connecting from anywhere in the app, the same way every time: a small
/// "Connecting" dialog, the trust and password questions, a clear message
/// when it fails.
abstract final class HostConnector {
  static ConnectPrompter prompterFor(BuildContext context) => DialogPrompter(context);

  /// Connects (or reuses an open connection). Returns null when the user
  /// cancelled or it failed; failures are explained in a dialog.
  static Future<LiveSession?> connect(BuildContext context, Host host) async {
    final sessions = AppScope.sessions(context);
    final existing = sessions.sessionFor(host.id);
    if (existing != null) return existing;

    final navigator = Navigator.of(context, rootNavigator: true);
    var progressShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConnectingDialog(host: host),
    ).whenComplete(() => progressShown = false);

    void hideProgress() {
      if (progressShown) navigator.pop();
    }

    try {
      final session = await sessions.connect(host, _ProgressAwarePrompter(DialogPrompter(context), hideProgress));
      hideProgress();
      return session;
    } on ConnectCancelled {
      hideProgress();
      return null;
    } on ConnectFailure catch (failure) {
      hideProgress();
      if (context.mounted) await _FailureDialog.show(context, failure);
      return null;
    } catch (e) {
      hideProgress();
      if (context.mounted) await _FailureDialog.show(context, ConnectFailure('The connection failed', '$e'));
      return null;
    }
  }

  /// Connects and opens a terminal, or shows the terminal already open.
  static Future<void> openTerminal(BuildContext context, Host host) async {
    final session = await connect(context, host);
    if (session == null || !context.mounted) return;
    if (session.terminals.isNotEmpty && !session.terminals.last.ended) {
      await TerminalScreen.open(context, session, session.terminals.last);
    } else {
      await TerminalScreen.openNew(context, session);
    }
  }
}

/// Hides the "Connecting" dialog before any question is asked, so the
/// question is not hidden behind it.
class _ProgressAwarePrompter implements ConnectPrompter {
  _ProgressAwarePrompter(this._inner, this._hideProgress);

  final ConnectPrompter _inner;
  final VoidCallback _hideProgress;

  @override
  Future<bool> trustNewHost(String host, int port, key) {
    _hideProgress();
    return _inner.trustNewHost(host, port, key);
  }

  @override
  Future<bool> acceptChangedHost(String host, int port, key, KnownHost? previous) {
    _hideProgress();
    return _inner.acceptChangedHost(host, port, key, previous);
  }

  @override
  Future<SecretAnswer?> askPassword(String host, String username, {required bool wasWrong}) {
    _hideProgress();
    return _inner.askPassword(host, username, wasWrong: wasWrong);
  }

  @override
  Future<SecretAnswer?> askPassphrase(StoredKey key, {required bool wasWrong}) {
    _hideProgress();
    return _inner.askPassphrase(key, wasWrong: wasWrong);
  }
}

class _ConnectingDialog extends StatelessWidget {
  const _ConnectingDialog({required this.host});

  final Host host;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 20),
          Expanded(child: Text('Connecting to ${host.title}')),
        ],
      ),
    );
  }
}

class _FailureDialog extends StatelessWidget {
  const _FailureDialog(this.failure);

  final ConnectFailure failure;

  static Future<void> show(BuildContext context, ConnectFailure failure) =>
      showDialog<void>(context: context, builder: (_) => _FailureDialog(failure));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.cloud_off_outlined, color: Theme.of(context).colorScheme.error),
      title: Text(failure.title),
      content: Text(failure.detail),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    );
  }
}
