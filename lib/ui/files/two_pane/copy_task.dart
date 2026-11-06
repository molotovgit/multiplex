import 'package:flutter/material.dart';

import '../../../src/rust/api/sftp.dart';
import '../../../src/rust/api/sftp_types.dart';
import '../../../src/rust/api/transfer.dart';
import '../../../src/rust/api/transfer_types.dart';
import '../transfer_queue.dart';

/// The core's copy call; tests pass a fake.
typedef Copier =
    Future<CopyReport> Function({
      required FileSide from,
      required String fromPath,
      required FileSide to,
      required String toDir,
      required ConflictPolicy onConflict,
      required FileTransfer transfer,
    });

/// Copies one file or folder from one pane's folder into the other's.
class CopyTask extends TransferTask {
  CopyTask({
    required this.from,
    required this.entry,
    required this.to,
    required this.toDir,
    required this.toLabel,
    required this.policy,
    Copier? copier,
  }) : _copy = copier ?? copyItem;

  final FileSide from;
  final RemoteEntry entry;
  final FileSide to;
  final String toDir;

  /// The other side's name, for the transfer list: "web-1".
  final String toLabel;
  final ConflictPolicy policy;
  final Copier _copy;

  @override
  String get name => entry.name;

  @override
  TransferDirection get direction => TransferDirection.copy;

  @override
  String get remoteFolder => toDir;

  /// Two copies to the same target would share one ".part" file.
  @override
  String get exclusiveKey => 'copy:$toLabel:${to.join(dir: toDir, name: entry.name)}';

  @override
  Future<String> run(FileTransfer transfer) async {
    final report = await _copy(from: from, fromPath: entry.path, to: to, toDir: toDir, onConflict: policy, transfer: transfer);
    final skipped = report.skipped == 0 ? '' : ' (${report.skipped} skipped: already there, or links to folders)';
    return '$toLabel: ${report.target}$skipped';
  }
}

/// Asks what to do when copied items are already in the target folder.
abstract final class ConflictDialog {
  static Future<ConflictPolicy?> ask(BuildContext context, {required List<String> names, required String folder}) {
    final title = names.length == 1 ? '"${names.first}" is already there' : '${names.length} items are already there';
    return showDialog<ConflictPolicy>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          'The folder $folder already has ${names.length == 1 ? 'something with this name' : 'items with these names'}. '
          'Replace overwrites files there; a folder is merged. Skip copies only what is missing. Keep both adds a number to the new name.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ConflictPolicy.skip), child: const Text('Skip')),
          TextButton(onPressed: () => Navigator.pop(context, ConflictPolicy.keepBoth), child: const Text('Keep both')),
          FilledButton(onPressed: () => Navigator.pop(context, ConflictPolicy.replace), child: const Text('Replace')),
        ],
      ),
    );
  }
}
