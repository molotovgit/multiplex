import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../src/rust/api/ssh_types.dart';
import '../common/dialog_prompter.dart';
import '../common/widgets.dart';
import '../keys/page_width.dart';
import 'remote_runner.dart';
import 'run_output_view.dart';

/// A command to run on a host, and how to describe its result.
class RemoteJob {
  const RemoteJob({required this.title, required this.command, this.judge, this.showCommand = true});

  final String title;
  final String command;

  /// Gives a custom verdict for the result; null shows the plain
  /// exit-code verdict.
  final RemoteVerdict Function(ExecOutput output)? judge;

  /// False for long helper commands that would only be noise on screen.
  final bool showCommand;
}

/// A bottom sheet that connects to a host, runs one command and shows
/// what happened. Closing it while the command runs stops the command if
/// the connection was opened just for it.
class RemoteRunSheet extends StatefulWidget {
  const RemoteRunSheet({super.key, required this.host, required this.job});

  final Host host;
  final RemoteJob job;

  static Future<void> show(BuildContext context, {required Host host, required RemoteJob job}) {
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => RemoteRunSheet(host: host, job: job),
    );
  }

  @override
  State<RemoteRunSheet> createState() => _RemoteRunSheetState();
}

class _RemoteRunSheetState extends State<RemoteRunSheet> {
  late RemoteRunner _runner;
  bool _running = false;
  RemoteOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _runner = RemoteRunner(AppScope.sessions(context));
    // Start after the first frame, so the connection's questions (trust
    // this server? password?) can open dialogs on top of this sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (_outcome == null) _runner.cancel();
    super.dispose();
  }

  /// After a failure: start again with a fresh connection attempt.
  void _retry() {
    setState(() {
      _outcome = null;
      _running = false;
      _runner = RemoteRunner(AppScope.sessions(context));
    });
    _start();
  }

  Future<void> _start() async {
    if (!mounted) return;
    final runner = _runner;
    final outcome = await runner.run(
      widget.host,
      widget.job.command,
      DialogPrompter(context),
      onRunning: () {
        if (mounted) setState(() => _running = true);
      },
    );
    if (!mounted || runner != _runner) return;
    if (outcome is RemoteCancelled) {
      _close();
      return;
    }
    setState(() => _outcome = outcome);
  }

  /// Closes this sheet, even if something else was opened on top of it.
  void _close() {
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.pop(context);
    } else {
      Navigator.removeRoute(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final job = widget.job;
    // The sheet only keeps clear of the top; this keeps the buttons clear
    // of the gesture bar at the bottom.
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.title, style: text.titleLarge),
                  const SizedBox(height: 4),
                  Text('On ${widget.host.title} (${widget.host.target})', style: text.bodyMedium?.copyWith(color: colors.muted)),
                  if (job.showCommand) ...[
                    const SizedBox(height: 8),
                    MonoText(job.command, maxLines: 3, style: text.bodySmall?.copyWith(color: colors.muted)),
                  ],
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                // A short fade when progress turns into the result.
                child: AnimatedSwitcher(
                  duration: PageLayout.fade,
                  child: _RunBody(key: ValueKey(_outcome?.runtimeType), host: widget.host, job: job, running: _running, outcome: _outcome),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _RunActions(outcome: _outcome, onClose: _close, onRetry: _retry),
            ),
          ],
        ),
      ),
    );
  }
}

/// The buttons under the result: stop while working, close when done,
/// and try again after a failure.
class _RunActions extends StatelessWidget {
  const _RunActions({required this.outcome, required this.onClose, required this.onRetry});

  final RemoteOutcome? outcome;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: switch (outcome) {
        null => [TextButton(onPressed: onClose, child: const Text('Stop and close'))],
        RemoteFailed() => [
          TextButton(onPressed: onClose, child: const Text('Close')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ],
        _ => [FilledButton(onPressed: onClose, child: const Text('Close'))],
      },
    );
  }
}

/// The middle of the sheet: progress while working, then the result.
class _RunBody extends StatelessWidget {
  const _RunBody({super.key, required this.host, required this.job, required this.running, required this.outcome});

  final Host host;
  final RemoteJob job;
  final bool running;
  final RemoteOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    return switch (outcome) {
      null => RunProgress(label: running ? 'Running the command…' : 'Connecting to ${host.title}…'),
      RemoteFinished(:final output) => RunOutputView(output: output, verdict: job.judge?.call(output)),
      RemoteFailed(:final title, :final detail) => RunFailure(title: title, detail: detail),
      RemoteCancelled() => const SizedBox.shrink(),
    };
  }
}

/// A spinner with a line saying what is happening.
class RunProgress extends StatelessWidget {
  const RunProgress({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 16),
        Expanded(child: Text(label)),
      ],
    );
  }
}

/// Why connecting or running failed.
class RunFailure extends StatelessWidget {
  const RunFailure({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VerdictLine(ok: false, message: title),
        if (detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 36),
            child: SelectableText(detail, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted)),
          ),
      ],
    );
  }
}
