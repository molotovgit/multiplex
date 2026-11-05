import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../common/widgets.dart';
import 'file_format.dart';
import 'files_widgets.dart';
import 'transfer_queue.dart';

/// Words for the transfer list.
abstract final class TransferText {
  /// One line about the whole queue, for the compact bar.
  static String summary(TransferQueue queue) {
    final running = queue.runningCount;
    final waiting = queue.waitingCount;
    if (running == 1 && waiting == 0) {
      final job = queue.jobs.firstWhere((j) => j.state == TransferState.running);
      return '${job.direction == TransferDirection.upload ? 'Uploading' : 'Downloading'} ${job.name}';
    }
    if (running > 0 || waiting > 0) {
      final parts = [if (running > 0) '$running running', if (waiting > 0) '$waiting waiting'];
      return 'Transfers: ${parts.join(', ')}';
    }
    final failed = queue.countIn(TransferState.failed);
    final done = queue.countIn(TransferState.done);
    if (failed > 0) return '$failed ${failed == 1 ? 'transfer' : 'transfers'} failed, $done done';
    return 'All transfers finished';
  }

  /// One line about a single job.
  static String status(TransferJob job) => switch (job.state) {
    TransferState.waiting => 'Waiting',
    TransferState.running => FileSizes.progress(job.transferred, job.total),
    TransferState.done => job.direction == TransferDirection.download ? 'Saved to ${job.result}' : 'Uploaded to ${job.result}',
    TransferState.failed => 'Failed: ${job.error}',
    TransferState.cancelled => 'Cancelled',
  };
}

/// A slim bar under the file list while anything is transferring (or
/// has just finished). Tap it to see every transfer.
class TransferPanel extends StatelessWidget {
  const TransferPanel({super.key, required this.queue});

  final TransferQueue queue;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    // Grows into view when the first transfer starts, so the user sees
    // where it went.
    return AnimatedSize(
      duration: FilesMotion.short(context),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: ListenableBuilder(
        listenable: queue,
        builder: (context, _) {
          if (queue.jobs.isEmpty) return const SizedBox(width: double.infinity);
          final active = queue.activeCount > 0;
          final failed = queue.countIn(TransferState.failed) > 0;
          return Material(
            color: colors.surface,
            child: SafeArea(
              top: false,
              child: Semantics(
                button: true,
                label: 'Show transfers',
                child: InkWell(
                  onTap: () => TransferSheet.show(context, queue),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: colors.outline)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          active ? Icons.swap_vert : (failed ? Icons.error_outline : Icons.check_circle_outline),
                          color: failed && !active ? colors.danger : colors.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(TransferText.summary(queue), maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (active) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(value: queue.overallFraction, borderRadius: BorderRadius.circular(2)),
                              ],
                            ],
                          ),
                        ),
                        if (!active) ...[const SizedBox(width: 8), TextButton(onPressed: queue.clearFinished, child: const Text('Clear'))],
                        const SizedBox(width: 8),
                        Icon(Icons.expand_less, color: colors.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Every transfer with its progress, and buttons to cancel or clear.
class TransferSheet extends StatelessWidget {
  const TransferSheet({super.key, required this.queue});

  final TransferQueue queue;

  static Future<void> show(BuildContext context, TransferQueue queue) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TransferSheet(queue: queue),
  );

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.7),
        child: ListenableBuilder(
          listenable: queue,
          builder: (context, _) {
            final jobs = queue.jobs.reversed.toList();
            final hasFinished = jobs.any((j) => !j.isActive);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  'Transfers',
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (queue.activeCount > 1) TextButton(onPressed: queue.cancelAll, child: const Text('Cancel all')),
                      if (hasFinished) TextButton(onPressed: queue.clearFinished, child: const Text('Clear finished')),
                    ],
                  ),
                ),
                if (jobs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Text('Nothing is transferring. Uploads and downloads you start show up here.'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: jobs.length,
                      itemBuilder: (context, i) => TransferRow(job: jobs[i], onCancel: () => queue.cancel(jobs[i])),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One transfer: name, what is happening, progress, and its button.
class TransferRow extends StatelessWidget {
  const TransferRow({super.key, required this.job, required this.onCancel});

  final TransferJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final upload = job.direction == TransferDirection.upload;
    final failed = job.state == TransferState.failed;
    final savedPath = job.state == TransferState.done && !upload ? job.result : null;
    return ListTile(
      leading: Icon(upload ? Icons.upload_outlined : Icons.download_outlined, semanticLabel: upload ? 'Upload' : 'Download'),
      title: Text(job.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TransferText.status(job),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: failed ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.danger) : null,
          ),
          if (job.state == TransferState.running) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: job.fraction, borderRadius: BorderRadius.circular(2)),
          ],
        ],
      ),
      trailing: job.isActive
          ? IconButton(tooltip: 'Cancel transfer', icon: const Icon(Icons.close), onPressed: onCancel)
          : savedPath != null
          ? IconButton(
              tooltip: 'Copy saved path',
              icon: const Icon(Icons.content_copy),
              onPressed: () => Toast.copy(context, savedPath, what: 'Path copied'),
            )
          : null,
    );
  }
}
