import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'host_picker.dart';
import 'remote_run_sheet.dart';

/// "Run on a host": pick a saved host, run the command there and show
/// its output, error output and exit code.
abstract final class SnippetRunner {
  static Future<void> run(BuildContext context, {required String name, required String command}) async {
    if (command.trim().isEmpty) {
      Toast.show(context, 'Type a command first.');
      return;
    }
    final host = await HostPicker.pick(context, title: 'Run on which host?');
    if (host == null || !context.mounted) return;
    await RemoteRunSheet.show(
      context,
      host: host,
      job: RemoteJob(title: name.trim().isEmpty ? 'Run command' : 'Run "${name.trim()}"', command: command),
    );
  }
}
