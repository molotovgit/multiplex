import '../data/models.dart';
import '../data/vault_store.dart';
import '../src/rust/api/terminal_types.dart';
import 'connect_flow.dart';
import 'reconnector.dart';
import 'session_manager.dart';
import 'shell_launch.dart';

/// One attempt to bring a dropped [LiveSession] back: log in again with
/// what is saved, join every open terminal to the new connection, and
/// restart the tunnels that were running.
class SessionRestore {
  SessionRestore({required this.store, required this.session, required this.shellOptions, required this.stillOpen, ConnectFlow? flow})
      // The session was approved when it opened (fingerprint included, on
      // hosts that ask for it), so a reconnect does not ask again.
      : _flow = flow ?? ConnectFlow(store, const SilentPrompter(), ownerConfirmed: true);

  final VaultStore store;
  final LiveSession session;
  final ShellOptions Function(Host host, int number) shellOptions;

  /// False once the user closed the session meanwhile.
  final bool Function() stillOpen;
  final ConnectFlow _flow;

  /// Why the last attempt gave up, for the terminal's banner.
  String? failure;

  /// The banner text for a reconnect [status].
  static String note(ReconnectStatus status) {
    if (status.trying) return 'Reconnecting… (try ${status.attempt})';
    final at = status.nextTryAt;
    if (at == null) return 'Reconnecting…';
    final secs = at.difference(DateTime.now()).inSeconds.clamp(1, 999);
    return 'Reconnecting… next try in $secs s';
  }

  Future<ReconnectResult> tryOnce() async {
    final host = store.host(session.host.id) ?? session.host;
    try {
      final ssh = await _flow.connect(host);
      if (!stillOpen()) {
        await ssh.disconnect();
        return ReconnectResult.giveUp;
      }
      final old = session.ssh;
      session.ssh = ssh;
      // The old connection is dead; let it go quietly.
      old.disconnect().ignore();
      for (final terminal in List.of(session.terminals)) {
        if (terminal.ended) continue;
        try {
          await ssh.reattachShell(shell: terminal.shell, options: shellOptions(host, terminal.number));
          terminal.reconnected();
        } catch (e) {
          terminal.connectionGone('Could not reopen this terminal ($e).');
        }
      }
      await _restartTunnels();
      return ReconnectResult.connected;
    } on ConnectCancelled {
      failure = 'Logging in again needs you (a password that is not saved, a one-time code, or a new server key). Tap Reconnect.';
      return ReconnectResult.giveUp;
    } on ConnectFailure catch (e) {
      failure = 'The connection was lost and could not be restored: ${e.title}.';
      return ReconnectResult.retry;
    }
  }

  Future<void> _restartTunnels() async {
    for (final running in List.of(session.tunnels)) {
      try {
        final tunnel = await session.ssh.startTunnel(spec: running.rule.spec);
        final index = session.tunnels.indexOf(running);
        if (index >= 0) session.tunnels[index] = RunningTunnel(running.rule, tunnel);
      } catch (_) {
        // The tunnel can be started again from the Tunnels screen.
        session.tunnels.remove(running);
      }
    }
  }
}
