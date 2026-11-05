import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../sessions/connect_flow.dart';
import '../../src/rust/api/ssh_types.dart';
import 'widgets.dart';

/// Answers the connection's questions with dialogs.
class DialogPrompter implements ConnectPrompter {
  DialogPrompter(this.context);

  final BuildContext context;

  @override
  Future<bool> trustNewHost(String host, int port, HostKeyInfo key) async {
    if (!context.mounted) return false;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _HostKeyDialog(
        title: 'New server',
        message: 'This is the first connection to $host${port == 22 ? '' : ':$port'}. '
            'Check that this fingerprint matches the server before you trust it.',
        key_: key,
        actionLabel: 'Trust and connect',
      ),
    );
    return answer ?? false;
  }

  @override
  Future<bool> acceptChangedHost(String host, int port, HostKeyInfo key, KnownHost? previous) async {
    if (!context.mounted) return false;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _HostKeyDialog(
        title: 'Server identity changed',
        message: 'The key of $host is not the one you trusted before. Someone may be intercepting the connection. '
            'Only continue if you know the server was reinstalled or its key was replaced.',
        key_: key,
        previous: previous,
        actionLabel: 'Replace key and connect',
        warning: true,
      ),
    );
    return answer ?? false;
  }

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

  Future<SecretAnswer?> _askSecret({required String title, required String message, required String label, required String rememberLabel}) {
    if (!context.mounted) return Future.value(null);
    return showDialog<SecretAnswer>(
      context: context,
      builder: (context) => _SecretDialog(title: title, message: message, label: label, rememberLabel: rememberLabel),
    );
  }
}

class _HostKeyDialog extends StatelessWidget {
  const _HostKeyDialog({
    required this.title,
    required this.message,
    required this.key_,
    required this.actionLabel,
    this.previous,
    this.warning = false,
  });

  final String title;
  final String message;
  final HostKeyInfo key_;
  final KnownHost? previous;
  final String actionLabel;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      icon: Icon(warning ? Icons.gpp_bad_outlined : Icons.fingerprint, color: warning ? colors.danger : colors.accent),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            Text(previous == null ? key_.algorithm : 'New key (${key_.algorithm})', style: text.labelMedium?.copyWith(color: colors.muted)),
            const SizedBox(height: 4),
            MonoText(key_.fingerprint, selectable: true),
            if (previous != null) ...[
              const SizedBox(height: 12),
              Text('Trusted before (${previous!.algorithm})', style: text.labelMedium?.copyWith(color: colors.muted)),
              const SizedBox(height: 4),
              MonoText(previous!.fingerprint, selectable: true),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: warning ? FilledButton.styleFrom(backgroundColor: colors.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(actionLabel),
        ),
      ],
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
