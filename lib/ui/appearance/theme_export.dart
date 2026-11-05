import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../app/theme_spec.dart';
import '../common/widgets.dart';
import 'theme_import.dart';
import 'theme_pack_file.dart';

/// A theme as Multiplex's own JSON, the format "Import theme" reads back.
abstract final class ThemeExport {
  static String json(ThemeSpec theme) => const JsonEncoder.withIndent('  ').convert(theme.toJson());

  /// "Tokyo Night copy" -> "tokyo-night-copy.json".
  static String fileName(ThemeSpec theme, {bool withPictures = false}) {
    final slug = theme.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'theme' : slug}${withPictures ? '-with-pictures' : ''}.json';
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

  /// Saves the theme alone, or with its pictures in the same file.
  Future<void> _saveFile(BuildContext context, {bool withPictures = false}) async {
    final name = ThemeExport.fileName(theme, withPictures: withPictures);
    try {
      final text = withPictures ? await ThemePackFile.write(theme) : json;
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: utf8.encode(text),
        mimeType: 'application/json',
        dialogTitle: 'Save theme',
      );
      if (saved == null || !context.mounted) return;
      Toast.show(context, 'Saved $name');
      Navigator.pop(context);
    } on ThemeImportException catch (e) {
      if (context.mounted) Toast.show(context, e.message);
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
            if (theme.backgrounds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'The text holds the colours and style only. To take the ${theme.backgrounds.length} background '
                '${theme.backgrounds.length == 1 ? 'picture' : 'pictures'} along, save the file with pictures.',
              ),
            ],
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
        if (theme.backgrounds.isNotEmpty)
          OutlinedButton(onPressed: () => _saveFile(context, withPictures: true), child: const Text('Save with pictures')),
        FilledButton(onPressed: () => _saveFile(context), child: const Text('Save as file')),
      ],
    );
  }
}
