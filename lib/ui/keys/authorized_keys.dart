import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../src/rust/api/ssh_types.dart';
import '../snippets/host_picker.dart';
import '../snippets/remote_run_sheet.dart';
import '../snippets/run_output_view.dart';

/// Quoting for POSIX shells (sh, bash, zsh, dash).
abstract final class ShellQuote {
  /// Wraps [value] in single quotes, so the shell takes it literally. A
  /// single quote inside is written as '\'' (close the quotes, add an
  /// escaped quote, open them again).
  static String single(String value) => "'${value.replaceAll("'", r"'\''")}'";
}

/// Builds the command that adds a public key to a server's
/// ~/.ssh/authorized_keys, and reads its result.
abstract final class AuthorizedKeys {
  /// Printed by the command when the key was added.
  static const addedMarker = 'VAULTTERM_KEY_ADDED';

  /// Printed by the command when the key was already there.
  static const presentMarker = 'VAULTTERM_KEY_PRESENT';

  /// The public key as one clean line.
  static String keyLine(String publicOpenssh) => publicOpenssh.trim().split(RegExp(r'[\r\n]+')).first.trim();

  /// The key type and data without the comment, for example
  /// "ssh-ed25519 AAAA...". A key counts as installed when this part is
  /// in the file, even with a different comment or with options in front.
  static String keyBody(String line) => line.split(RegExp(r'\s+')).take(2).join(' ');

  /// One command for SSH exec. It creates ~/.ssh (mode 700) and
  /// ~/.ssh/authorized_keys (mode 600), then adds the key line unless it
  /// is already there. If the file does not end with a line break, one is
  /// added first so the key does not get glued to the last line.
  ///
  /// The script runs under `sh -c` so it works the same when the user's
  /// login shell is not a POSIX shell (fish, csh). It is all on one line
  /// because csh does not allow line breaks inside quotes.
  static String installCommand(String publicOpenssh) {
    final line = keyLine(publicOpenssh);
    final body = keyBody(line);
    final script = [
      'umask 077',
      r'mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" || exit 1',
      r'f="$HOME/.ssh/authorized_keys"',
      r'touch "$f" && chmod 600 "$f" || exit 1',
      'if grep -qF -- ${ShellQuote.single(body)} "\$f"; then echo $presentMarker; exit 0; fi',
      r'if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then echo >> "$f"; fi',
      'printf ${ShellQuote.single(r'%s\n')} ${ShellQuote.single(line)} >> "\$f" && echo $addedMarker',
    ].join('; ');
    return 'sh -c ${ShellQuote.single(script)}';
  }

  /// What to tell the user once the command has finished.
  static RemoteVerdict verdict(ExecOutput output, String hostTitle) {
    if (output.exitCode == 0 && output.stdout.contains(presentMarker)) {
      return RemoteVerdict(ok: true, message: 'This key was already installed on $hostTitle.', showOutput: false);
    }
    if (output.exitCode == 0 && output.stdout.contains(addedMarker)) {
      return RemoteVerdict(
        ok: true,
        message: 'Key installed on $hostTitle. To log in with it, edit the host and choose this key.',
        showOutput: false,
      );
    }
    final code = output.exitCode == null ? '' : ' (exit code ${output.exitCode})';
    final said = output.stdout.trim().isEmpty && output.stderr.trim().isEmpty ? '' : ' The server said:';
    return RemoteVerdict(ok: false, message: 'Could not install the key on $hostTitle$code.$said');
  }
}

/// "Install on a server": pick a saved host, connect, add the key.
abstract final class KeyInstaller {
  static Future<void> install(BuildContext context, StoredKey key) async {
    final host = await HostPicker.pick(context, title: 'Install the key on which server?');
    if (host == null || !context.mounted) return;
    await RemoteRunSheet.show(
      context,
      host: host,
      job: RemoteJob(
        title: 'Install "${key.name}"',
        command: AuthorizedKeys.installCommand(key.publicOpenssh),
        showCommand: false,
        judge: (output) => AuthorizedKeys.verdict(output, host.title),
      ),
    );
  }
}
