import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../common/widgets.dart';

/// Shows a paste before it runs: why it was stopped, the text itself in
/// a scrollable monospace box, and Paste / Cancel.
class PasteConfirmDialog extends StatelessWidget {
  const PasteConfirmDialog({super.key, required this.text, required this.reasons});

  final String text;
  final List<String> reasons;

  /// True when the user chose Paste.
  static Future<bool> ask(BuildContext context, String text, List<String> reasons) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => PasteConfirmDialog(text: text, reasons: reasons),
    );
    return ok ?? false;
  }

  /// Taller previews scroll, so the buttons always stay on screen.
  static const previewHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return AlertDialog(
      title: const Text('Paste this?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(reason),
              ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Text to paste',
              child: Container(
                constraints: const BoxConstraints(maxHeight: previewHeight),
                width: double.maxFinite,
                decoration: BoxDecoration(
                  color: colors.raised,
                  border: Border.all(color: colors.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: MonoText(text, style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Paste')),
      ],
    );
  }
}
