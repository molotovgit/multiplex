import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../src/rust/api/ssh_types.dart';
import '../common/widgets.dart';

/// A short judgement of a finished command: did it work, and what to say.
class RemoteVerdict {
  const RemoteVerdict({required this.ok, required this.message, this.showOutput = true});

  final bool ok;
  final String message;

  /// False when the message says it all and the raw output would only
  /// confuse (for example after a key was installed).
  final bool showOutput;

  /// The plain verdict for any command: exit code 0 means it worked.
  factory RemoteVerdict.fromExitCode(ExecOutput output) => switch (output.exitCode) {
    null => const RemoteVerdict(ok: true, message: 'Finished. The server did not report an exit code.'),
    0 => const RemoteVerdict(ok: true, message: 'Finished with exit code 0'),
    final code => RemoteVerdict(ok: false, message: 'Finished with exit code $code'),
  };
}

/// Sizes for showing command output.
abstract final class OutputLimits {
  /// Showing more than this many characters makes the screen slow; the
  /// copy button still copies everything.
  static const shownChars = 100000;
}

/// The result of a finished command: the verdict, then the output and the
/// error output, each with its own copy button.
class RunOutputView extends StatelessWidget {
  const RunOutputView({super.key, required this.output, this.verdict});

  final ExecOutput output;

  /// Overrides the plain exit-code verdict.
  final RemoteVerdict? verdict;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final shown = verdict ?? RemoteVerdict.fromExitCode(output);
    final printedNothing = output.stdout.isEmpty && output.stderr.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VerdictLine(ok: shown.ok, message: shown.message),
        if (output.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('The output was cut off after 1 MiB.', style: text.bodyMedium?.copyWith(color: colors.muted)),
          ),
        if (shown.showOutput) ...[
          if (output.stdout.isNotEmpty) OutputBlock(label: 'Output', text: output.stdout, copyLabel: 'Copy output'),
          if (output.stderr.isNotEmpty) OutputBlock(label: 'Error output', text: output.stderr, copyLabel: 'Copy error output'),
          if (printedNothing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('The command printed nothing.', style: text.bodyMedium?.copyWith(color: colors.muted)),
            ),
        ],
      ],
    );
  }
}

/// An icon and a sentence saying whether something worked.
class VerdictLine extends StatelessWidget {
  const VerdictLine({super.key, required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline, color: ok ? colors.live : colors.danger),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// One stream of output in a terminal-font box, with a copy button.
class OutputBlock extends StatelessWidget {
  const OutputBlock({super.key, required this.label, required this.text, required this.copyLabel});

  final String label;
  final String text;
  final String copyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final tooLong = text.length > OutputLimits.shownChars;
    final shown = tooLong ? text.substring(0, OutputLimits.shownChars) : text;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.muted, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: copyLabel,
                icon: const Icon(Icons.copy_outlined),
                onPressed: () => Toast.copy(context, text, what: 'Copied ${label.toLowerCase()}'),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(10)),
            child: MonoText(shown, selectable: true, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (tooLong)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Showing the start only. Copy it to get all of it.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
