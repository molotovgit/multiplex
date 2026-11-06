import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/otp_account.dart';
import '../keys/code_widgets.dart';

/// The server asks for a one-time code. Codes linked to the host are
/// offered as buttons (one tap fills and sends); any code can be typed.
class CodePromptDialog extends StatefulWidget {
  const CodePromptDialog({super.key, required this.host, required this.prompt, required this.linked, required this.wasWrong, this.clock});

  final String host;
  final String prompt;
  final List<OtpAccount> linked;
  final bool wasWrong;
  final CodeClock? clock;

  static Future<String?> show(BuildContext context, String host, String prompt, List<OtpAccount> linked, {required bool wasWrong}) {
    if (!context.mounted) return Future.value(null);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CodePromptDialog(host: host, prompt: prompt, linked: linked, wasWrong: wasWrong),
    );
  }

  @override
  State<CodePromptDialog> createState() => _CodePromptDialogState();
}

class _CodePromptDialogState extends State<CodePromptDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _send(String code) => Navigator.pop(context, code.replaceAll(' ', ''));

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final question = widget.prompt.isEmpty ? 'Verification code' : widget.prompt;
    return AlertDialog(
      icon: Icon(Icons.pin_outlined, color: colors.accent),
      title: const Text('Verification code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.host} asks: "$question"'),
            if (widget.wasWrong) ...[
              const SizedBox(height: 8),
              Text('The last login was refused. Codes change often, so use the current one.', style: text.bodyMedium?.copyWith(color: colors.danger)),
            ],
            if (widget.linked.isNotEmpty)
              CodeTicker(
                clock: widget.clock,
                builder: (context, now) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final account in widget.linked)
                      if (currentCode(account, now) case final code?)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            onPressed: () => _send(code),
                            child: Row(
                              children: [
                                Expanded(child: Text('Use ${account.title}', overflow: TextOverflow.ellipsis)),
                                CodeText(code, style: text.titleMedium),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _typed,
              autofocus: widget.linked.isEmpty,
              keyboardType: TextInputType.number,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (v) => v.trim().isEmpty ? null : _send(v),
              decoration: InputDecoration(labelText: widget.linked.isEmpty ? 'Code' : 'Or type a code'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _typed,
          builder: (context, _) => FilledButton(onPressed: _typed.text.trim().isEmpty ? null : () => _send(_typed.text), child: const Text('Connect')),
        ),
      ],
    );
  }
}
