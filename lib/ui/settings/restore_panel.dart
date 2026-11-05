import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';
import 'backup_controllers.dart';
import 'backup_widgets.dart';
import 'settings_widgets.dart';

/// The restore steps in one card: choose a file, type its password, then
/// add it to the current data or replace everything. Each step has one
/// main button and a way back.
class RestorePanel extends StatelessWidget {
  const RestorePanel({super.key, required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final stage = controller.stage;
          // Typing the password and opening share a key, so the password
          // field keeps its text while the backup opens.
          final step = stage == RestoreStage.opening ? RestoreStage.enterPassword : stage;
          return BackupCard(
            children: [
              FadeChange(
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: switch (step) {
                    RestoreStage.chooseFile => _ChooseFileStep(controller: controller),
                    RestoreStage.enterPassword || RestoreStage.opening => _PasswordStep(controller: controller),
                    RestoreStage.chooseMode => _ModeStep(controller: controller),
                    RestoreStage.finished => _FinishedStep(controller: controller),
                  },
                ),
              ),
            ],
          );
        },
      );
}

/// "Step 2 of 3: ..." above each step, so the user knows how far along
/// they are.
class _StepLabel extends StatelessWidget {
  const _StepLabel(this.number, this.text);

  final int number;
  final String text;

  static const steps = 3;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          'Step $number of $steps: $text',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      );
}

/// Children of a step, stacked with even gaps.
class _StepColumn extends StatelessWidget {
  const _StepColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            children[i],
          ],
        ],
      );
}

class _ChooseFileStep extends StatelessWidget {
  const _ChooseFileStep({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) => _StepColumn(
        children: [
          const _StepLabel(1, 'choose the backup file'),
          const HelpText('Brings back hosts, keys, snippets, known hosts, tunnels, themes and settings from a backup file.'),
          if (controller.error != null) NoticeBox(tone: NoticeTone.error, text: controller.error!),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choose backup file'),
              onPressed: controller.picking ? null : controller.chooseFile,
            ),
          ),
        ],
      );
}

/// The password for the picked backup, and "Open backup".
class _PasswordStep extends StatefulWidget {
  const _PasswordStep({required this.controller});

  final RestoreController controller;

  @override
  State<_PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<_PasswordStep> {
  final _password = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    FocusScope.of(context).unfocus();
    await widget.controller.open(_password.text);
    if (!mounted) return;
    if (widget.controller.stage == RestoreStage.enterPassword) {
      // Wrong password: put the cursor back with the text selected, so
      // the user can retype straight away.
      _focus.requestFocus();
      _password.selection = TextSelection(baseOffset: 0, extentOffset: _password.text.length);
    } else {
      // Once opened the password is no longer needed.
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colors = AppColorsTheme.of(context);
    final opening = controller.stage == RestoreStage.opening;
    return _StepColumn(
      children: [
        const _StepLabel(2, 'type its password'),
        Row(
          children: [
            Icon(Icons.description_outlined, color: colors.muted),
            const SizedBox(width: 12),
            Expanded(child: MonoText(controller.fileName ?? '', maxLines: 2)),
          ],
        ),
        PasswordField(
          controller: _password,
          focusNode: _focus,
          enabled: !opening,
          label: 'Backup password',
          errorText: controller.error,
          autofillHint: AutofillHints.password,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _open(),
          onChanged: (_) => controller.clearError(),
        ),
        if (opening) const BusyNote('Opening the backup...'),
        // Wraps onto two lines on narrow phones or with large text.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Open backup'),
              onPressed: opening ? null : _open,
            ),
            TextButton(onPressed: opening ? null : controller.chooseFile, child: const Text('Choose another file')),
            TextButton(onPressed: opening ? null : controller.startOver, child: const Text('Cancel')),
          ],
        ),
      ],
    );
  }
}

/// What the backup holds, and the two ways to bring it in. The
/// destructive one is set apart, in the danger colour, and asks first.
class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.controller});

  final RestoreController controller;

  void _finish(BuildContext context, {required bool replace}) {
    controller.apply(replace: replace);
    AppScope.sessions(context).applyTerminalTheme();
    Toast.show(context, 'Backup restored');
  }

  Future<void> _replace(BuildContext context) async {
    final ok = await Confirm.ask(
      context,
      title: 'Replace everything?',
      message: 'Your current hosts, keys, snippets, known hosts, tunnels, themes and settings are deleted '
          'and the backup takes their place. This cannot be undone.',
      action: 'Replace everything',
    );
    if (ok && context.mounted) _finish(context, replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final incoming = controller.incoming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepLabel(3, 'choose how to bring it in'),
        const NoticeBox(tone: NoticeTone.success, title: 'Backup opened', text: 'It holds:'),
        const SizedBox(height: 16),
        if (incoming != null) BackupSummaryView(summary: incoming),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.merge_type),
            label: const Text('Add to current data'),
            onPressed: () => _finish(context, replace: false),
          ),
        ),
        const SizedBox(height: 8),
        const HelpText('Keeps what you have. Items that are in both are updated from the backup.'),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: colors.danger, side: BorderSide(color: colors.danger)),
            icon: const Icon(Icons.restore_page_outlined),
            label: const Text('Replace everything'),
            onPressed: () => _replace(context),
          ),
        ),
        const SizedBox(height: 8),
        const HelpText('Deletes your current data first, then loads the backup and its settings.'),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: controller.startOver, child: const Text('Cancel')),
        ),
      ],
    );
  }
}

/// Says what came in.
class _FinishedStep extends StatelessWidget {
  const _FinishedStep({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    final what = result?.summary.describe() ?? 'the backup';
    return _StepColumn(
      children: [
        NoticeBox(
          tone: NoticeTone.success,
          title: 'Restore finished',
          text: result?.replaced ?? false
              ? 'Your data was replaced with $what from the backup, and its settings.'
              : 'Added $what from the backup. Everything you had is still here.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: controller.startOver, child: const Text('Restore another backup')),
        ),
      ],
    );
  }
}
