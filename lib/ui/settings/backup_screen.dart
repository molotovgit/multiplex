import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../common/widgets.dart';
import 'backup_controllers.dart';
import 'backup_service.dart';
import 'backup_widgets.dart';
import 'restore_panel.dart';
import 'settings_widgets.dart';

/// Export the whole vault to one password-protected file, or bring such a
/// file back. Export and restore sit on separate tabs, so each view has
/// one main button.
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
  // The controllers live here, so a restore in progress survives
  // switching tabs.
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
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Backup & restore'),
            bottom: const TabBar(tabs: [Tab(text: 'Export'), Tab(text: 'Restore')]),
          ),
          body: TabBarView(
            children: [
              _TabPage(child: ExportPanel(controller: _export)),
              _TabPage(child: RestorePanel(controller: _restore)),
            ],
          ),
        ),
      );
}

/// One tab's scrolling page, at reading width.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ContentWidth(
        maxWidth: SettingsLayout.maxReadingWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, SettingsLayout.gutter, SettingsLayout.gutter, 32),
          children: [child],
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
  final _passwordFocus = FocusNode();
  final _repeatFocus = FocusNode();

  /// Check the fields as the user types only after a first try, so they
  /// are not told off before they have finished.
  bool _tried = false;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    _passwordFocus.dispose();
    _repeatFocus.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _tried = true);
    if (!(_form.currentState?.validate() ?? false)) {
      // Put the cursor in the first field that needs fixing.
      final first = BackupPassword.check(_password.text) != null ? _passwordFocus : _repeatFocus;
      first.requestFocus();
      return;
    }
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
                focusNode: _passwordFocus,
                enabled: !busy,
                label: 'Backup password',
                helper: 'At least ${BackupPassword.minLength} characters',
                autofillHint: AutofillHints.newPassword,
                textInputAction: TextInputAction.next,
                validator: (value) => BackupPassword.check(value ?? ''),
              ),
              PasswordField(
                controller: _repeat,
                focusNode: _repeatFocus,
                enabled: !busy,
                label: 'Type the password again',
                autofillHint: AutofillHints.newPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _export(),
                validator: (value) => BackupPassword.checkRepeat(_password.text, value ?? ''),
              ),
              FadeChange(child: _ExportStatus(key: ValueKey(_ExportStatus.keyFor(controller)), controller: controller)),
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

/// The line under the fields: progress while working, then the result or
/// what went wrong. Empty before the first export.
class _ExportStatus extends StatelessWidget {
  const _ExportStatus({super.key, required this.controller});

  final ExportController controller;

  /// Changes whenever the shown message changes, so it fades over.
  static String keyFor(ExportController c) => '${c.stage.name}|${c.error}|${c.result?.fileName}';

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    return switch (controller.stage) {
      ExportStage.encrypting => const BusyNote('Encrypting the backup...'),
      ExportStage.saving => const BusyNote('Choose where to save the backup.'),
      ExportStage.idle when controller.error != null => NoticeBox(tone: NoticeTone.error, text: controller.error!),
      ExportStage.idle when result != null => NoticeBox(
          tone: NoticeTone.success,
          title: 'Backup saved',
          text: '${result.fileName} holds ${result.summary.describe()}, plus your settings.',
        ),
      ExportStage.idle => const SizedBox(width: double.infinity),
    };
  }
}
