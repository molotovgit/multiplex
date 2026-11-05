import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

import '../../data/models.dart';
import '../../sessions/connect_flow.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/ssh_types.dart';

/// Limits for commands run on a host.
abstract final class RemoteLimits {
  /// Output beyond this is cut off by the core (1 MiB).
  static const outputBytes = 1024 * 1024;
}

/// Turns any error into a sentence that can be shown to people.
abstract final class ErrorText {
  static String of(Object error) => switch (error) {
        AnyhowException(:final message) => message,
        ConnectFailure(:final detail) => detail,
        _ => error.toString(),
      };
}

/// How running a command on a host ended.
sealed class RemoteOutcome {
  const RemoteOutcome();
}

/// The command ran; its output and exit code are in [output].
class RemoteFinished extends RemoteOutcome {
  const RemoteFinished(this.output);

  final ExecOutput output;
}

/// Connecting or running failed before the command could finish.
class RemoteFailed extends RemoteOutcome {
  const RemoteFailed(this.title, this.detail);

  final String title;
  final String detail;
}

/// The user stopped it (for example, did not trust the server).
class RemoteCancelled extends RemoteOutcome {
  const RemoteCancelled();
}

/// Connects to a saved host and runs one command there.
///
/// An open connection to the host is reused and left open. A connection
/// opened just for this command is closed again when it finishes, or when
/// [cancel] is called (which also stops a command that keeps running).
class RemoteRunner {
  RemoteRunner(this._sessions, {this.maxBytes = RemoteLimits.outputBytes});

  final SessionManager _sessions;
  final int maxBytes;

  LiveSession? _ownSession;
  bool _cancelled = false;

  Future<RemoteOutcome> run(Host host, String command, ConnectPrompter prompter, {VoidCallback? onRunning}) async {
    final reused = _sessions.sessionFor(host.id) != null;
    final LiveSession session;
    try {
      session = await _sessions.connect(host, prompter);
    } on ConnectCancelled {
      return const RemoteCancelled();
    } on ConnectFailure catch (failure) {
      return RemoteFailed(failure.title, failure.detail);
    } catch (error) {
      return RemoteFailed('Could not connect to ${host.title}', ErrorText.of(error));
    }
    if (!reused) _ownSession = session;
    if (_cancelled) {
      _closeOwnSession();
      return const RemoteCancelled();
    }

    onRunning?.call();
    try {
      final output = await session.ssh.exec(command: command, maxBytes: maxBytes);
      return RemoteFinished(output);
    } catch (error) {
      if (_cancelled) return const RemoteCancelled();
      return RemoteFailed('The command could not run', ErrorText.of(error));
    } finally {
      _closeOwnSession();
    }
  }

  /// Stops waiting. Closes the connection if this runner opened it.
  void cancel() {
    _cancelled = true;
    _closeOwnSession();
  }

  void _closeOwnSession() {
    final own = _ownSession;
    _ownSession = null;
    // Closing happens in the background: the result is already known and
    // a failure to close cleanly changes nothing for the user.
    if (own != null) _sessions.disconnect(own).ignore();
  }
}
