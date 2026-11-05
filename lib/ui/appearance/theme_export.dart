import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../app/theme_spec.dart';
import '../common/widgets.dart';

/// A theme as VaultTerm's own JSON, the format "Import theme" reads back.
abstract final class ThemeExport {
  static String json(ThemeSpec theme) => const JsonEncoder.withIndent('  ').convert(theme.toJson());

  /// "Tokyo Night copy" -> "tokyo-night-copy.json".
  static String fileName(ThemeSpec theme) {
    final slug = theme.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'theme' : slug}.json';
  }
}

/// Copies a theme to the clipboard as JSON, then offers to save it as a
/// file too.
class ThemeExportDialog extends StatelessWidget {
  const ThemeExportDialog({super.key, required this.theme, required this.json});

  final ThemeSpec theme;
  final String json;

  static Future<void> show(BuildContext context, ThemeSpec theme) async {
    final json = ThemeExport.json(theme);
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (_) => ThemeExportDialog(theme: theme, json: json));
  }

  Future<void> _saveFile(BuildContext context) async {
    final name = ThemeExport.fileName(theme);
    try {
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: utf8.encode(json),
        mimeType: 'application/json',
        dialogTitle: 'Save theme',
      );
      if (saved == null || !context.mounted) return;
      Toast.show(context, 'Saved $name');
      Navigator.pop(context);
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not save the file ($e). Try another folder.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return AlertDialog(
      title: const Text('Export theme'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('"${theme.name}" is copied to the clipboard. Paste it into Import theme on another device, or save it as a file.'),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                child: MonoText(json, selectable: true, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: () => _saveFile(context), child: const Text('Save as file')),
      ],
    );
  }
}
