import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'backup_service.dart';

/// A password field with a button to show or hide what was typed.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.errorText,
    this.validator,
    this.autofillHint,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  /// An error set from outside, such as "wrong password".
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final String? autofillHint;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        enabled: widget.enabled,
        obscureText: !_visible,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        autofillHints: widget.autofillHint == null ? null : [widget.autofillHint!],
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        validator: widget.validator,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          errorText: widget.errorText,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            tooltip: _visible ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ),
      );
}

/// The counts in a backup as a row of small tiles: "3 hosts", "2 keys"...
class BackupSummaryView extends StatelessWidget {
  const BackupSummaryView({super.key, required this.summary});

  final BackupSummary summary;

  static const _icons = [Icons.dns_outlined, Icons.key_outlined, Icons.bolt_outlined, Icons.verified_user_outlined, Icons.palette_outlined];

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final parts = summary.parts;
    return Semantics(
      label: summary.describe(),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < parts.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.raised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icons[i], size: 16, color: parts[i].$1 == 0 ? colors.muted : colors.accent),
                    const SizedBox(width: 6),
                    Text(parts[i].$2, style: TextStyle(color: parts[i].$1 == 0 ? colors.muted : colors.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A card with a title and its contents spaced evenly.
class BackupCard extends StatelessWidget {
  const BackupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                children[i],
              ],
            ],
          ),
        ),
      );
}
