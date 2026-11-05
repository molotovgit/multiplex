import 'package:flutter/material.dart';

/// A hidden text field for a passphrase, with a button to show what was
/// typed.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: _hidden,
      enableSuggestions: false,
      autocorrect: false,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show passphrase' : 'Hide passphrase',
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

/// Passphrase and "repeat passphrase" for a new key. The second field
/// only shows once something is typed in the first, and must match it.
class NewPassphraseFields extends StatelessWidget {
  const NewPassphraseFields({super.key, required this.passphrase, required this.confirm, this.enabled = true});

  final TextEditingController passphrase;
  final TextEditingController confirm;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: passphrase,
      builder: (context, _) => Column(
        children: [
          SecretField(
            controller: passphrase,
            enabled: enabled,
            label: 'Passphrase (optional)',
            helper: 'Protects the key if someone copies it. Leave empty for no passphrase.',
            textInputAction: TextInputAction.next,
          ),
          if (passphrase.text.isNotEmpty) ...[
            const SizedBox(height: 16),
            SecretField(
              controller: confirm,
              enabled: enabled,
              label: 'Repeat passphrase',
              validator: (value) => value == passphrase.text ? null : 'The two passphrases are not the same. Type them again.',
            ),
          ],
        ],
      ),
    );
  }
}
