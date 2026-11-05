import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';
import 'backup_controllers.dart';
import 'backup_widgets.dart';
import 'settings_widgets.dart';

/// The restore steps in one card: choose a file, type its password, then
/// add it to the current data or replace everything.
class RestorePanel extends StatelessWidget {
  const RestorePanel({super.key, required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => BackupCard(
          children: switch (controller.stage) {
            RestoreStage.chooseFile => [
                const HelpText('Brings back hosts, keys, snippets, known hosts, tunnels, themes and settings from a backup file.'),
                if (controller.error != null) NoticeBox(tone: NoticeTone.error, text: controller.error!),
                _ChooseFileButton(controller: controller),
              ],
            RestoreStage.enterPassword || RestoreStage.opening => [
                _PickedFileRow(controller: controller),
                _PasswordStep(controller: controller),
              ],
            RestoreStage.chooseMode => [_ModeStep(controller: controller)],
            RestoreStage.finished => [_FinishedStep(controller: controller)],
          },
        ),
      );
}

class _ChooseFileButton extends StatelessWidget {
  const _ChooseFileButton({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose backup file'),
          onPressed: controller.picking ? null : controller.chooseFile,
        ),
      );
}

/// The chosen file's name, with a way to pick a different one.
class _PickedFileRow extends StatelessWidget {
  const _PickedFileRow({required this.controller});

  final RestoreController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final busy = controller.stage == RestoreStage.opening || controller.picking;
    return Row(
      children: [
        Icon(Icons.description_outlined, color: colors.muted),
        const SizedBox(width: 10),
        Expanded(child: MonoText(controller.fileName ?? '', maxLines: 2)),
        TextButton(onPressed: busy ? null : controller.chooseFile, child: const Text('Choose another file')),
      ],
    );
  }
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

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    FocusScope.of(context).unfocus();
    await widget.controller.open(_password.text);
    // Once opened the password is no longer needed.
    if (mounted && widget.controller.stage == RestoreStage.chooseMode) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final opening = controller.stage == RestoreStage.opening;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PasswordField(
          controller: _password,
          enabled: !opening,
          label: 'Backup password',
          errorText: controller.error,
          autofillHint: AutofillHints.password,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _open(),
          onChanged: (_) => controller.clearError(),
        ),
        const SizedBox(height: 14),
        if (opening) ...[
          const BusyNote('Opening the backup...'),
          const SizedBox(height: 14),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Open backup'),
            onPressed: opening ? null : _open,
          ),
        ),
      ],
    );
  }
}

/// What the backup holds, and the two ways to bring it in.
class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.controller});

  final RestoreController controller;

  void _add(BuildContext context) {
    controller.apply(replace: false);
    AppScope.sessions(context).applyTerminalTheme();
  }

  Future<void> _replace(BuildContext context) async {
    final ok = await Confirm.ask(
      context,
      title: 'Replace everything?',
      message: 'Your current hosts, keys, snippets, known hosts, tunnels, themes and settings are deleted '
          'and the backup takes their place. This cannot be undone.',
      action: 'Replace everything',
    );
    if (!ok || !context.mounted) return;
    controller.apply(replace: true);
    AppScope.sessions(context).applyTerminalTheme();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final incoming = controller.incoming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NoticeBox(tone: NoticeTone.success, title: 'Backup opened', text: 'Choose how to bring it in.'),
        const SizedBox(height: 14),
        if (incoming != null) BackupSummaryView(summary: incoming),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            icon: const Icon(Icons.merge_type),
            label: const Text('Add to current data'),
            onPressed: () => _add(context),
          ),
        ),
        const SizedBox(height: 6),
        const HelpText('Keeps what you have. Items that are in both are updated from the backup.'),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: colors.danger, side: BorderSide(color: colors.danger)),
            icon: const Icon(Icons.restore_page_outlined),
            label: const Text('Replace everything'),
            onPressed: () => _replace(context),
          ),
        ),
        const SizedBox(height: 6),
        const HelpText('Deletes your current data first, then loads the backup and its settings.'),
        const SizedBox(height: 12),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoticeBox(
          tone: NoticeTone.success,
          title: 'Restore finished',
          text: result?.replaced ?? false
              ? 'Your data was replaced with $what from the backup, and its settings.'
              : 'Added $what from the backup. Everything you had is still here.',
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: controller.startOver, child: const Text('Restore another backup')),
        ),
      ],
    );
  }
}
