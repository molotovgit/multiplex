import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../../src/rust/api/keys.dart' show KeyPairInfo;
import '../common/widgets.dart';
import 'key_labels.dart';
import 'key_tools.dart';
import 'mono_style.dart';
import 'page_width.dart';
import 'passphrase_fields.dart';

/// Checks pasted key text before it goes to the core, to catch the
/// common mistakes with a clearer message.
abstract final class KeyText {
  /// Key files are a few kilobytes; anything much bigger is the wrong file.
  static const maxFileBytes = 64 * 1024;

  /// Returns what is wrong with [text], or null if it is worth checking.
  static String? problem(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Paste the private key, or choose the key file.';
    final looksPublic =
        trimmed.startsWith('ssh-') ||
        trimmed.startsWith('ecdsa-') ||
        trimmed.startsWith('sk-') ||
        trimmed.contains('BEGIN SSH2 PUBLIC KEY') ||
        trimmed.contains('BEGIN PUBLIC KEY');
    if (looksPublic) return 'This is a public key. Import the private key instead: the file without ".pub" at the end.';
    return null;
  }

  /// A sentence for each kind of [KeyProblem].
  static String explain(Object error) {
    if (error is! KeyProblem) return 'Could not read the key. Details: $error';
    return switch (error.kind) {
      KeyProblemKind.passphraseNeeded => 'This key is protected. Enter its passphrase, then check the key again.',
      KeyProblemKind.wrongPassphrase => 'That passphrase does not unlock the key. Check it and try again.',
      KeyProblemKind.unreadable => 'This is not a private key Multiplex can read. Paste the whole key, including the BEGIN and END lines.',
      KeyProblemKind.failed => 'Could not read the key. Details: ${error.detail}',
    };
  }
}

/// Brings in a private key the user already has, pasted or read from a
/// file. The key is checked (and its fingerprint shown) before it can be
/// saved. Hands the finished key to [onCreated].
class ImportKeyForm extends StatefulWidget {
  const ImportKeyForm({super.key, required this.tools, required this.onCreated});

  final KeyTools tools;
  final ValueChanged<StoredKey> onCreated;

  @override
  State<ImportKeyForm> createState() => _ImportKeyFormState();
}

class _ImportKeyFormState extends State<ImportKeyForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pem = TextEditingController();
  final _passphrase = TextEditingController();
  bool _needsPassphrase = false;
  bool _savePassphrase = true;
  bool _busy = false;

  /// The key as the core read it; set once the check passed.
  KeyPairInfo? _checked;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pem.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  /// New key text: the old check no longer counts, and the passphrase
  /// field shows only if this text needs one.
  void _pemChanged() {
    setState(() {
      _checked = null;
      _error = null;
      _needsPassphrase = widget.tools.isEncrypted(_pem.text.trim());
    });
  }

  void _passphraseChanged() {
    if (_checked != null || _error != null) {
      setState(() {
        _checked = null;
        _error = null;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Choose a private key file');
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > KeyText.maxFileBytes) {
        setState(() => _error = 'That file is too big to be a key. Choose the private key file, for example id_ed25519.');
        return;
      }
      _pem.text = utf8.decode(bytes, allowMalformed: true);
      if (_name.text.trim().isEmpty) _name.text = file.name;
      _pemChanged();
      if (!_needsPassphrase) await _check();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the file. Try again, or paste the key text here instead. Details: $error');
    }
  }

  Future<void> _check() async {
    final pem = _pem.text.trim();
    final mistake = KeyText.problem(pem);
    if (mistake != null) {
      setState(() => _error = mistake);
      return;
    }
    final encrypted = widget.tools.isEncrypted(pem);
    if (encrypted && _passphrase.text.isEmpty) {
      setState(() {
        _needsPassphrase = true;
        _error = 'This key is protected. Enter its passphrase, then check the key again.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _needsPassphrase = encrypted;
    });
    try {
      final info = await widget.tools.inspect(pem, passphrase: encrypted ? _passphrase.text : null);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _checked = info;
        if (_name.text.trim().isEmpty) _name.text = info.comment.trim().isEmpty ? 'Imported key' : info.comment.trim();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = KeyText.explain(error);
        if (error is KeyProblem && error.kind == KeyProblemKind.passphraseNeeded) _needsPassphrase = true;
      });
    }
  }

  void _save() {
    final info = _checked;
    if (info == null || !(_form.currentState?.validate() ?? false)) return;
    widget.onCreated(
      StoredKey(
        id: VaultStore.newId(),
        name: _name.text.trim(),
        privatePem: info.privatePem,
        publicOpenssh: info.publicOpenssh,
        fingerprint: info.fingerprint,
        algorithm: info.algorithm,
        passphrase: info.encrypted && _savePassphrase ? _passphrase.text : null,
        encrypted: info.encrypted,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checked = _checked;
    return Form(
      key: _form,
      child: Column(
        children: [
          Expanded(
            child: PageWidth(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  FormRow(
                    child: TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.sentences,
                      validator: (value) => (value ?? '').trim().isEmpty ? 'Enter a name for the key.' : null,
                      decoration: const InputDecoration(labelText: 'Name', hintText: 'For example: Office server key'),
                    ),
                  ),
                  FormRow(
                    child: TextField(
                      controller: _pem,
                      enabled: !_busy,
                      minLines: 4,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: MonoStyle.of(context, Theme.of(context).textTheme.bodySmall),
                      onChanged: (_) => _pemChanged(),
                      decoration: const InputDecoration(
                        labelText: 'Private key',
                        hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  FormRow(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickFile,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Choose key file'),
                      ),
                    ),
                  ),
                  if (_needsPassphrase) ...[
                    FormRow(
                      child: SecretField(
                        controller: _passphrase,
                        enabled: !_busy,
                        label: 'Passphrase',
                        helper: 'This key is protected. Enter the passphrase that was set when the key was made.',
                        onChanged: (_) => _passphraseChanged(),
                        onSubmitted: (_) => _check(),
                      ),
                    ),
                    SwitchListTile(
                      value: _savePassphrase,
                      onChanged: _busy ? null : (value) => setState(() => _savePassphrase = value),
                      title: const Text('Save passphrase in the vault'),
                      subtitle: Text(
                        _savePassphrase
                            ? 'Multiplex unlocks the key for you when you connect.'
                            : 'Multiplex asks for the passphrase each time you connect.',
                      ),
                    ),
                  ],
                  if (checked != null) FormRow(child: KeyPreview(info: checked)),
                ],
              ),
            ),
          ),
          BottomActionBar(
            note: _error,
            noteIsError: true,
            action: FilledButton.icon(
              onPressed: _busy ? null : (checked == null ? _check : _save),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(checked == null ? Icons.fact_check_outlined : Icons.save_outlined),
              label: Text(_busy ? 'Checking key…' : (checked == null ? 'Check key' : 'Save key')),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the check found: type, fingerprint, whether it is protected, and
/// whether the keychain already has it.
class KeyPreview extends StatelessWidget {
  const KeyPreview({super.key, required this.info});

  final KeyPairInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final existing = AppScope.store(context).keys.where((k) => k.fingerprint == info.fingerprint).firstOrNull;
    final type = KeyAlgorithms.label(info.algorithm);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: colors.live, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Key checked: $type', style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (info.comment.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Comment: ${info.comment.trim()}', style: text.bodyMedium?.copyWith(color: colors.muted)),
            ],
            const SizedBox(height: 8),
            MonoText(info.fingerprint, selectable: true, style: text.bodySmall),
            if (info.encrypted) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: colors.muted),
                  const SizedBox(width: 8),
                  Text('Protected by a passphrase', style: text.bodySmall?.copyWith(color: colors.muted)),
                ],
              ),
            ],
            if (existing != null) ...[
              const SizedBox(height: 8),
              Text('You already have this key in the keychain as "${existing.name}".', style: text.bodySmall?.copyWith(color: colors.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
