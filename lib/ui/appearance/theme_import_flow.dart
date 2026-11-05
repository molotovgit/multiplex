import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/terminal_fonts.dart';
import '../../app/theme_spec.dart';
import '../common/widgets.dart';
import 'theme_actions.dart';
import 'theme_download.dart';
import 'theme_import.dart';

/// Where an imported theme comes from.
enum ThemeImportSource { file, paste, link }

/// "Import theme": the user picks where the theme comes from, VaultTerm
/// reads it, and the editor opens so the user can look it over and save it.
class ThemeImportFlow {
  ThemeImportFlow(this.context, {ThemeImporter? importer, ThemeDownloader? downloader})
      : importer = importer ?? ThemeImporter(),
        downloader = downloader ?? ThemeDownloader();

  final BuildContext context;
  final ThemeImporter importer;
  final ThemeDownloader downloader;

  Future<void> start() async {
    final source = await showModalBottomSheet<ThemeImportSource>(context: context, builder: (_) => const _ImportSourceSheet());
    if (source == null || !context.mounted) return;
    final theme = await _readFrom(source);
    if (theme == null || !context.mounted) return;
    await ThemeActions(context).review(theme);
  }

  /// Reads a theme from the chosen place. Null when the user cancels or
  /// the theme could not be read (the user has been told why).
  Future<ThemeSpec?> _readFrom(ThemeImportSource source) => switch (source) {
        ThemeImportSource.file => _fromFile(),
        ThemeImportSource.paste => showDialog<ThemeSpec>(context: context, builder: (_) => PasteThemeDialog(importer: importer)),
        ThemeImportSource.link => showDialog<ThemeSpec>(
            context: context,
            builder: (_) => LinkThemeDialog(importer: importer, downloader: downloader),
          ),
      };

  /// Any file may be a theme: many have no extension at all, so the
  /// content decides, not the name.
  Future<ThemeSpec?> _fromFile() async {
    try {
      final file = await FilePicker.pickFile(dialogTitle: 'Import theme');
      if (file == null) return null;
      final size = file.lengthSync() ?? await file.length();
      if (size != null && size > ThemeImporter.maxBytes) throw ThemeImportException.tooBig;
      final text = ThemeImporter.decode(await file.readAsBytes());
      return importer.read(text, sourceName: ThemeSourceName.fromFileName(file.name));
    } on ThemeImportException catch (e) {
      if (context.mounted) Toast.show(context, e.message);
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not open the file ($e). Try again or pick another file.');
    }
    return null;
  }
}

/// The three ways to bring in a theme.
class _ImportSourceSheet extends StatelessWidget {
  const _ImportSourceSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Scrolls when large text makes the choices taller than the sheet.
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Import theme', style: text.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Alacritty, Kitty and Ghostty themes work, and themes exported from VaultTerm. You can check and change the colours before saving.',
                    style: text.bodyMedium,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Choose a file'),
              subtitle: const Text('.toml, .conf, .json, or a theme file with no extension'),
              onTap: () => Navigator.pop(context, ThemeImportSource.file),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Paste text'),
              subtitle: const Text('The contents of a theme file'),
              onTap: () => Navigator.pop(context, ThemeImportSource.paste),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Download from a link'),
              subtitle: const Text('An https link to a theme file, GitHub pages included'),
              onTap: () => Navigator.pop(context, ThemeImportSource.link),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A box to paste theme text into. Problems show under the box so the
/// user can fix the text and try again.
class PasteThemeDialog extends StatefulWidget {
  const PasteThemeDialog({super.key, required this.importer});

  final ThemeImporter importer;

  @override
  State<PasteThemeDialog> createState() => _PasteThemeDialogState();
}

class _PasteThemeDialogState extends State<PasteThemeDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || !mounted) return;
    setState(() {
      _text.text = data!.text!;
      _error = null;
    });
  }

  void _import() {
    try {
      Navigator.pop(context, widget.importer.read(_text.text));
    } on ThemeImportException catch (e) {
      setState(() => _error = e.message);
    } on Exception catch (e) {
      setState(() => _error = 'This theme could not be read ($e).');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Paste a theme'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _pasteClipboard,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Paste from clipboard'),
                ),
              ),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 6,
                maxLines: 12,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: TerminalFonts.jetbrains.family, letterSpacing: 0),
                decoration: InputDecoration(
                  hintText: '[colors.primary]\nbackground = "#1a1b26"\n...',
                  errorText: _error,
                  errorMaxLines: 4,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _import, child: const Text('Import theme')),
        ],
      );
}

/// Asks for an https link, downloads the theme and reads it. Problems
/// show under the link so the user can correct it.
class LinkThemeDialog extends StatefulWidget {
  const LinkThemeDialog({super.key, required this.importer, required this.downloader});

  final ThemeImporter importer;
  final ThemeDownloader downloader;

  @override
  State<LinkThemeDialog> createState() => _LinkThemeDialogState();
}

class _LinkThemeDialogState extends State<LinkThemeDialog> {
  final _link = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final download = await widget.downloader.fetch(_link.text);
      final theme = widget.importer.read(download.text, sourceName: download.sourceName);
      if (mounted) Navigator.pop(context, theme);
    } on ThemeImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'The download failed ($e). Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Download a theme'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _link,
                autofocus: true,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _busy ? null : _download(),
                decoration: InputDecoration(
                  labelText: 'Link',
                  hintText: 'https://github.com/…/theme.toml',
                  helperText: 'Links to a file page on GitHub work too.',
                  errorText: _error,
                  errorMaxLines: 4,
                ),
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _busy ? null : _download, child: const Text('Download theme')),
        ],
      );
}
