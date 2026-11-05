import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../app/theme_spec.dart';
import 'theme_import.dart';
import 'theme_repo_install.dart';

/// A theme the dialog installed, and how many pictures were left out.
class InstalledTheme {
  const InstalledTheme(this.theme, this.skipped);

  /// Not saved yet; its pictures are already in its folder.
  final ThemeSpec theme;
  final int skipped;
}

/// "Install theme from link": a GitHub theme repository, such as an
/// Omarchy theme, with its background pictures. Closes with an
/// [InstalledTheme], or null when cancelled.
class InstallThemeDialog extends StatefulWidget {
  const InstallThemeDialog({super.key, required this.installer});

  final ThemeRepoInstaller installer;

  @override
  State<InstallThemeDialog> createState() => _InstallThemeDialogState();
}

class _InstallThemeDialogState extends State<InstallThemeDialog> {
  final _link = TextEditingController();
  String? _error;

  /// What is being downloaded; null when nothing is running.
  String? _step;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _link.text = data!.text!.trim());
  }

  Future<void> _install() async {
    setState(() {
      _error = null;
      _step = 'Starting';
    });
    try {
      final pack = await widget.installer.download(_link.text, onStep: (step) {
        if (mounted) setState(() => _step = step);
      });
      // Closed while downloading: keep nothing.
      if (!mounted) return;
      setState(() => _step = 'Saving the pictures');
      final theme = await widget.installer.build(pack);
      if (mounted) Navigator.pop(context, InstalledTheme(theme, pack.skipped));
    } on ThemeImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not install the theme ($e). Try again.');
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColorsTheme.of(context).muted;
    final busy = _step != null;
    return AlertDialog(
      title: const Text('Install theme from link'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste the link of a GitHub theme repository, such as an Omarchy theme. Multiplex takes its colours and up to 10 background pictures.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              enabled: !busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'GitHub link',
                hintText: 'https://github.com/owner/theme',
                errorText: _error,
                errorMaxLines: 4,
                suffixIcon: IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste), onPressed: busy ? null : _paste),
              ),
              onSubmitted: (_) => busy ? null : _install(),
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_step!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _install, child: const Text('Install')),
      ],
    );
  }
}
