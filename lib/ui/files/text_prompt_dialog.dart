import 'package:flutter/material.dart';

import 'files_widgets.dart';

/// Asks for one line of text: a new name, a folder name or a path.
/// The button stays off while the field is empty, and [validate] can
/// refuse the text with a message shown under the field.
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.label,
    required this.action,
    this.initial = '',
    this.message,
    this.hint,
    this.validate,
    this.mono = false,
    this.selectStem = false,
  });

  final String title;
  final String label;

  /// Button text, saying what happens: "Rename", "Create folder".
  final String action;
  final String initial;
  final String? message;
  final String? hint;

  /// Returns what is wrong with the text, or null if it is fine.
  final String? Function(String text)? validate;

  /// Shows the text in the terminal font (for paths).
  final bool mono;

  /// Selects the name without its extension, so typing replaces just
  /// "notes" in "notes.txt".
  final bool selectStem;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String label,
    required String action,
    String initial = '',
    String? message,
    String? hint,
    String? Function(String text)? validate,
    bool mono = false,
    bool selectStem = false,
  }) => showDialog<String>(
    context: context,
    builder: (_) => TextPromptDialog(
      title: title,
      label: label,
      action: action,
      initial: initial,
      message: message,
      hint: hint,
      validate: validate,
      mono: mono,
      selectStem: selectStem,
    ),
  );

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void initState() {
    super.initState();
    final text = widget.initial;
    final dot = text.lastIndexOf('.');
    final end = widget.selectStem && dot > 0 ? dot : text.length;
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: end);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final problem = widget.validate?.call(text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null) ...[Text(message), const SizedBox(height: 16)],
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            style: widget.mono ? MonoStyle.of(context) : null,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: widget.label, hintText: widget.hint, errorText: _error, errorMaxLines: 3),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(onPressed: _controller.text.trim().isEmpty ? null : _submit, child: Text(widget.action)),
        ),
      ],
    );
  }
}
