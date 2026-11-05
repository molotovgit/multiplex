import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../../src/rust/api/keys.dart' show KeyKind;
import '../common/widgets.dart';
import 'key_labels.dart';
import 'key_tools.dart';
import 'page_width.dart';
import 'passphrase_fields.dart';

/// Creates a brand new key pair: name, type, comment and an optional
/// passphrase. Hands the finished key to [onCreated]; saving it is up to
/// the caller.
class GenerateKeyForm extends StatefulWidget {
  const GenerateKeyForm({super.key, required this.tools, required this.onCreated});

  final KeyTools tools;
  final ValueChanged<StoredKey> onCreated;

  @override
  State<GenerateKeyForm> createState() => _GenerateKeyFormState();
}

class _GenerateKeyFormState extends State<GenerateKeyForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _comment = TextEditingController(text: KeyComments.forName(''));
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  KeyKind _kind = KeyKinds.recommended;

  /// Once the user types their own comment, the name stops changing it.
  bool _commentEdited = false;
  bool _savePassphrase = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _nameChanged(String name) {
    if (!_commentEdited) _comment.text = KeyComments.forName(name);
  }

  Future<void> _generate() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final passphrase = _passphrase.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await widget.tools.generate(_kind, comment: _comment.text.trim(), passphrase: passphrase.isEmpty ? null : passphrase);
      // The screen may have been closed while the key was being made.
      if (!mounted) return;
      widget.onCreated(
        StoredKey(
          id: VaultStore.newId(),
          name: _name.text.trim(),
          privatePem: info.privatePem,
          publicOpenssh: info.publicOpenssh,
          fingerprint: info.fingerprint,
          algorithm: info.algorithm,
          passphrase: info.encrypted && _savePassphrase ? passphrase : null,
          encrypted: info.encrypted,
          createdAt: DateTime.now(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final detail = error is KeyProblem ? error.detail : error.toString();
      setState(() {
        _busy = false;
        _error = 'Could not create the key. Try again, or choose another type.\nDetails: $detail';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      textInputAction: TextInputAction.next,
                      onChanged: _nameChanged,
                      validator: (value) => (value ?? '').trim().isEmpty ? 'Enter a name for the key.' : null,
                      decoration: const InputDecoration(labelText: 'Name', hintText: 'For example: Work laptop'),
                    ),
                  ),
                  const SectionHeader('Type'),
                  RadioGroup<KeyKind>(
                    groupValue: _kind,
                    onChanged: (kind) {
                      if (kind != null) setState(() => _kind = kind);
                    },
                    child: Column(
                      children: [
                        for (final option in KeyKinds.options)
                          RadioListTile<KeyKind>(value: option.kind, enabled: !_busy, title: Text(option.label), subtitle: Text(option.hint)),
                      ],
                    ),
                  ),
                  const SectionHeader('Details'),
                  FormRow(
                    child: TextFormField(
                      controller: _comment,
                      enabled: !_busy,
                      autocorrect: false,
                      onChanged: (_) => _commentEdited = true,
                      decoration: const InputDecoration(
                        labelText: 'Comment',
                        helperText: 'Added to the end of the public key, so you can tell keys apart on a server.',
                        helperMaxLines: 2,
                      ),
                    ),
                  ),
                  FormRow(
                    child: NewPassphraseFields(passphrase: _passphrase, confirm: _confirm, enabled: !_busy),
                  ),
                  ListenableBuilder(
                    listenable: _passphrase,
                    builder: (context, _) => _passphrase.text.isEmpty
                        ? const SizedBox.shrink()
                        : SwitchListTile(
                            value: _savePassphrase,
                            onChanged: _busy ? null : (value) => setState(() => _savePassphrase = value),
                            title: const Text('Save passphrase in the vault'),
                            subtitle: Text(
                              _savePassphrase
                                  ? 'VaultTerm unlocks the key for you when you connect.'
                                  : 'VaultTerm asks for the passphrase each time you connect.',
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          BottomActionBar(
            note: _error ?? (_busy && KeyKinds.isSlow(_kind) ? 'RSA keys take a few seconds to create.' : null),
            noteIsError: _error != null,
            action: FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.key_outlined),
              label: Text(_busy ? 'Generating key…' : 'Generate key'),
            ),
          ),
        ],
      ),
    );
  }
}
