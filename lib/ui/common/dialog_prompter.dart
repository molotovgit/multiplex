import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/otp_account.dart';
import '../../sessions/connect_flow.dart';
import '../../src/rust/api/ssh_types.dart';
import '../hosts/host_key_pages.dart';
import 'code_prompt_dialog.dart';

/// Answers the connection's questions with dialogs.
class DialogPrompter implements ConnectPrompter {
  DialogPrompter(this.context);

  final BuildContext context;

  /// A full page, not a small dialog, so the fingerprint is easy to read.
  @override
  Future<bool> trustNewHost(String host, int port, HostKeyInfo key) => HostKeyPages.trustNew(context, host, port, key);

  /// A full warning page: what changed, what it can mean, how to check.
  @override
  Future<bool> acceptChangedHost(String host, int port, HostKeyInfo key, KnownHost? previous) =>
      HostKeyPages.acceptChanged(context, host, port, key, previous);

  @override
  Future<SecretAnswer?> askPassword(String host, String username, {required bool wasWrong}) {
    return _askSecret(
      title: wasWrong ? 'Password refused' : 'Password',
      message: wasWrong ? 'The server refused that password for $username@$host. Try again.' : 'Enter the password for $username@$host.',
      label: 'Password',
      rememberLabel: 'Save password for this host',
    );
  }

  @override
  Future<SecretAnswer?> askPassphrase(StoredKey key, {required bool wasWrong}) {
    return _askSecret(
      title: wasWrong ? 'Wrong passphrase' : 'Key passphrase',
      message: wasWrong ? 'That passphrase does not unlock "${key.name}". Try again.' : 'The key "${key.name}" is protected. Enter its passphrase.',
      label: 'Passphrase',
      rememberLabel: 'Save passphrase with the key',
    );
  }

  @override
  Future<String?> askCode(String host, String prompt, List<OtpAccount> linked, {required bool wasWrong}) =>
      CodePromptDialog.show(context, host, prompt, linked, wasWrong: wasWrong);

  Future<SecretAnswer?> _askSecret({required String title, required String message, required String label, required String rememberLabel}) {
    if (!context.mounted) return Future.value(null);
    return showDialog<SecretAnswer>(
      context: context,
      builder: (context) => _SecretDialog(title: title, message: message, label: label, rememberLabel: rememberLabel),
    );
  }
}

class _SecretDialog extends StatefulWidget {
  const _SecretDialog({required this.title, required this.message, required this.label, required this.rememberLabel});

  final String title;
  final String message;
  final String label;
  final String rememberLabel;

  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  final _controller = TextEditingController();
  bool _remember = false;
  bool _hidden = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, SecretAnswer(_controller.text, remember: _remember));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _hidden,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show' : 'Hide',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(widget.rememberLabel),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}
