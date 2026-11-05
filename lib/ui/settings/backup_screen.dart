import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../common/widgets.dart';
import 'backup_controllers.dart';
import 'backup_service.dart';
import 'backup_widgets.dart';
import 'restore_panel.dart';
import 'settings_widgets.dart';

/// Export the whole vault to one password-protected file, or bring such a
/// file back.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.cipher = const CoreBackupCipher(), this.files = const PickerBackupFiles()});

  /// Swapped for fakes in tests; the real ones use the Rust core and the
  /// platform's file windows.
  final BackupCipher cipher;
  final BackupFiles files;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final ExportController _export;
  late final RestoreController _restore;

  @override
  void initState() {
    super.initState();
    final store = AppScope.store(context);
    _export = ExportController(store: store, cipher: widget.cipher, files: widget.files);
    _restore = RestoreController(store: store, cipher: widget.cipher, files: widget.files);
  }

  @override
  void dispose() {
    _export.dispose();
    _restore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Backup & restore')),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 32),
            children: [
              const SectionHeader('Export a backup'),
              ExportPanel(controller: _export),
              const SectionHeader('Restore a backup'),
              RestorePanel(controller: _restore),
            ],
          ),
        ),
      );
}

/// Password, repeat, a clear warning, and "Export backup".
class ExportPanel extends StatefulWidget {
  const ExportPanel({super.key, required this.controller});

  final ExportController controller;

  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<ExportPanel> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  /// Check the fields as the user types only after a first try, so they
  /// are not told off before they have finished.
  bool _tried = false;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _tried = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final outcome = await widget.controller.export(_password.text);
    if (!mounted) return;
    switch (outcome) {
      case ExportOutcome.saved:
        // Do not keep the password around once the file is safe.
        _password.clear();
        _repeat.clear();
        setState(() => _tried = false);
        Toast.show(context, 'Backup saved');
      case ExportOutcome.cancelled:
        Toast.show(context, 'Nothing was saved. Export again to choose where the backup goes.');
      case ExportOutcome.failed:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, store]),
      builder: (context, _) {
        final busy = controller.busy;
        final result = controller.result;
        return Form(
          key: _form,
          autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: BackupCard(
            children: [
              const HelpText('Saves your hosts, keys, snippets, known hosts, tunnels, themes and settings in one encrypted file.'),
              BackupSummaryView(summary: BackupSummary.ofStore(store)),
              const NoticeBox(
                tone: NoticeTone.warning,
                title: 'Keep the file and the password safe',
                text: 'The backup contains your saved passwords and private keys. '
                    'Without the password you choose here, nobody can open it, not even you. It cannot be recovered.',
              ),
              PasswordField(
                controller: _password,
                enabled: !busy,
                label: 'Backup password',
                helper: 'At least ${BackupPassword.minLength} characters',
                autofillHint: AutofillHints.newPassword,
                textInputAction: TextInputAction.next,
                validator: (value) => BackupPassword.check(value ?? ''),
              ),
              PasswordField(
                controller: _repeat,
                enabled: !busy,
                label: 'Type the password again',
                autofillHint: AutofillHints.newPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _export(),
                validator: (value) => BackupPassword.checkRepeat(_password.text, value ?? ''),
              ),
              if (controller.stage == ExportStage.encrypting) const BusyNote('Encrypting the backup...'),
              if (controller.stage == ExportStage.saving) const BusyNote('Choose where to save the backup.'),
              if (controller.error != null) NoticeBox(tone: NoticeTone.error, text: controller.error!),
              if (result != null)
                NoticeBox(
                  tone: NoticeTone.success,
                  title: 'Backup saved',
                  text: '${result.fileName} holds ${result.summary.describe()}, plus your settings.',
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Export backup'),
                  onPressed: busy ? null : _export,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
