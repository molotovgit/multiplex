import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'passphrase_fields.dart';

/// Asks for a new name.
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, required this.title, required this.initial, required this.action});

  final String title;
  final String initial;
  final String action;

  /// Returns the new name, or null if cancelled.
  static Future<String?> ask(BuildContext context, {required String title, required String initial, required String action}) {
    return showDialog<String>(
      context: context,
      builder: (context) => RenameDialog(title: title, initial: initial, action: action),
    );
  }

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Asks for a key's passphrase and checks it before closing.
class PassphraseDialog extends StatefulWidget {
  const PassphraseDialog({super.key, required this.keyName, required this.check});

  final String keyName;

  /// Returns null when the passphrase unlocks the key, or a sentence
  /// saying what is wrong.
  final Future<String?> Function(String passphrase) check;

  /// Returns the checked passphrase, or null if cancelled.
  static Future<String?> ask(BuildContext context, {required String keyName, required Future<String?> Function(String) check}) {
    return showDialog<String>(
      context: context,
      builder: (context) => PassphraseDialog(keyName: keyName, check: check),
    );
  }

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passphrase = _controller.text;
    if (passphrase.isEmpty) {
      setState(() => _error = 'Enter the passphrase.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await widget.check(passphrase);
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _busy = false;
        _error = problem;
      });
      return;
    }
    Navigator.pop(context, passphrase);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return AlertDialog(
      title: const Text('Save passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter the passphrase of "${widget.keyName}". It is checked, then kept in the vault so you are not asked again.'),
          const SizedBox(height: 16),
          SecretField(controller: _controller, label: 'Passphrase', autofocus: true, enabled: !_busy, onSubmitted: (_) => _submit()),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_outline),
          label: Text(_busy ? 'Checking…' : 'Save passphrase'),
        ),
      ],
    );
  }
}
