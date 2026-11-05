import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import '../keys/mono_style.dart';
import '../keys/page_width.dart';
import '../keys/undo_toast.dart';
import 'snippet_runner.dart';

/// Creates or edits a snippet. Closes with the saved snippet, or with
/// null when the user goes back or deletes it.
class SnippetEditorScreen extends StatefulWidget {
  const SnippetEditorScreen({super.key, this.snippet});

  /// The snippet to edit; null makes a new one.
  final Snippet? snippet;

  static Future<Snippet?> open(BuildContext context, {Snippet? snippet}) {
    return Navigator.of(context).push<Snippet>(
      MaterialPageRoute(
        fullscreenDialog: snippet == null,
        builder: (context) => SnippetEditorScreen(snippet: snippet),
      ),
    );
  }

  @override
  State<SnippetEditorScreen> createState() => _SnippetEditorScreenState();
}

class _SnippetEditorScreenState extends State<SnippetEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.snippet?.name ?? '');
  late final _command = TextEditingController(text: widget.snippet?.command ?? '');
  late bool _runImmediately = widget.snippet?.runImmediately ?? true;

  bool get _isNew => widget.snippet == null;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final base = widget.snippet ?? Snippet(id: VaultStore.newId(), name: '', command: '');
    final saved = base.copyWith(name: _name.text.trim(), command: _command.text.trimRight(), runImmediately: _runImmediately);
    AppScope.store(context).saveSnippet(saved);
    Toast.show(context, 'Saved the snippet "${saved.name}"');
    Navigator.pop(context, saved);
  }

  Future<void> _delete() async {
    final snippet = widget.snippet;
    if (snippet == null) return;
    final store = AppScope.store(context);
    final sure = await Confirm.ask(
      context,
      title: 'Delete "${snippet.name}"?',
      message: 'The snippet is removed from Multiplex. You can undo this for a few seconds.',
      action: 'Delete snippet',
    );
    if (!sure || !mounted) return;
    // Undo puts it back (at the end of the list).
    UndoToast.show(context, 'Deleted the snippet "${snippet.name}"', () => store.saveSnippet(snippet));
    Navigator.pop(context);
    store.deleteSnippet(snippet.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'New snippet' : 'Edit snippet')),
      body: Form(
        key: _form,
        child: Column(
          children: [
            Expanded(
              child: PageWidth(
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  children: [
                    FormRow(
                      child: TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        validator: (value) => (value ?? '').trim().isEmpty ? 'Enter a name for the snippet.' : null,
                        decoration: const InputDecoration(labelText: 'Name', hintText: 'For example: Restart the web server'),
                      ),
                    ),
                    FormRow(
                      child: TextFormField(
                        controller: _command,
                        minLines: 3,
                        maxLines: 12,
                        keyboardType: TextInputType.multiline,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: MonoStyle.of(context),
                        validator: (value) => (value ?? '').trim().isEmpty ? 'Enter the command to run.' : null,
                        decoration: const InputDecoration(labelText: 'Command', hintText: 'sudo systemctl restart nginx', alignLabelWithHint: true),
                      ),
                    ),
                    SwitchListTile(
                      value: _runImmediately,
                      onChanged: (value) => setState(() => _runImmediately = value),
                      title: const Text('Press Enter after inserting'),
                      subtitle: Text(
                        _runImmediately
                            ? 'The command runs as soon as it is inserted into a terminal.'
                            : 'The command is typed in, and you press Enter yourself.',
                      ),
                    ),
                    FormRow(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => SnippetRunner.run(context, name: _name.text, command: _command.text),
                          icon: const Icon(Icons.play_arrow_outlined),
                          label: const Text('Run on a host'),
                        ),
                      ),
                    ),
                    if (!_isNew) ...[
                      const SizedBox(height: 16),
                      FormRow(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: colors.danger),
                            onPressed: _delete,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete snippet'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            BottomActionBar(
              action: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save snippet')),
            ),
          ],
        ),
      ),
    );
  }
}
