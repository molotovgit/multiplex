import '../data/models.dart';
import '../data/otp_account.dart';
import '../src/rust/api/ssh_types.dart';
import 'connect_flow.dart';

/// What a terminal runs on the server: the login shell with the host's
/// startup command, or a tmux session that a reconnect lands on again.
abstract final class ShellLaunch {
  /// The tmux session name of a host's terminal number [number].
  static String tmuxSession(int number) => 'multiplex-$number';

  /// Attaches to (or creates) the terminal's tmux session. Without tmux
  /// on the server it says so in one line and starts the login shell.
  ///
  /// Wrapped in `sh -c` so it works whatever the user's shell is (fish
  /// has no `{ ...; }`).
  static String tmuxCommand(int number) =>
      "sh -c 'command -v tmux >/dev/null 2>&1 && exec tmux new -A -s ${tmuxSession(number)}; "
      'echo "Multiplex: tmux is not installed here, so this is a plain shell."; '
      "exec \"\${SHELL:-/bin/sh}\" -l'";

  /// The command to run instead of the login shell, or null for none.
  static String? command(Host host, int number) => host.keepWithTmux ? tmuxCommand(number) : null;

  /// The command typed after login. tmux keeps its own screen, so the
  /// startup command only runs without it.
  static String? startupCommand(Host host) => host.keepWithTmux ? null : host.startupCommand;
}

/// Answers every question with "no": a reconnect only uses what is saved
/// and never asks the user, so it cannot keep asking in a loop.
class SilentPrompter implements ConnectPrompter {
  const SilentPrompter();

  @override
  Future<bool> trustNewHost(String host, int port, HostKeyInfo key) async => false;

  @override
  Future<bool> acceptChangedHost(String host, int port, HostKeyInfo key, KnownHost? previous) async => false;

  @override
  Future<SecretAnswer?> askPassword(String host, String username, {required bool wasWrong}) async => null;

  @override
  Future<SecretAnswer?> askPassphrase(StoredKey key, {required bool wasWrong}) async => null;

  @override
  Future<String?> askCode(String host, String prompt, List<OtpAccount> linked, {required bool wasWrong}) async => null;
}
