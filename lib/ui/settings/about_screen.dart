import '../../app/app_icons.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme_spec.dart';
import '../../src/rust/api/app.dart' as core;
import '../common/widgets.dart';
import 'settings_widgets.dart';

/// Facts about this build of the app.
abstract final class AboutFacts {
  static const appName = 'Multiplex';
  static const description = 'An open-source SSH client with SFTP, port forwarding and an encrypted vault.';
  static const sourceAddress = 'github.com/molotovgit/multiplex';
  static const sourceUrl = 'https://$sourceAddress';

  /// Where the colours of the popular themes were read from.
  static const themeSource = 'The colours of the popular schemes were read from the alacritty-theme collection (Apache-2.0). '
      'Each scheme keeps its own licence, named below.';
}

/// Reads the native core's version. A class so tests can swap it.
class CoreVersion {
  const CoreVersion();

  String read() {
    try {
      return core.coreVersion();
    } catch (_) {
      // The core is not loaded (for example in widget tests).
      return 'Not available';
    }
  }
}

/// Name, version, source code, licences and theme credits.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.version = const CoreVersion()});

  final CoreVersion version;

  @override
  Widget build(BuildContext context) {
    final coreVersion = version.read();
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _AppHeader(),
            ListTile(
              leading: const AppIcon(AppIcons.memory),
              title: const Text('Core version'),
              subtitle: MonoText(coreVersion),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Source code'),
              subtitle: const MonoText(AboutFacts.sourceAddress, selectable: true),
              trailing: IconButton(
                icon: const Icon(Icons.content_copy_outlined),
                tooltip: 'Copy address',
                onPressed: () => Toast.copy(context, AboutFacts.sourceUrl, what: 'Address copied'),
              ),
            ),
            ListTile(
              leading: const AppIcon(AppIcons.gavel),
              title: const Text('Open-source licences'),
              subtitle: const Text('The software and fonts Multiplex is built with'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: AboutFacts.appName,
                applicationVersion: 'Core $coreVersion',
              ),
            ),
            const SectionHeader('Theme credits'),
            const Padding(
              padding: EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 8),
              child: HelpText(AboutFacts.themeSource),
            ),
            for (final theme in BuiltInThemes.all) _ThemeCredit(theme: theme),
          ],
        ),
      ),
    );
  }
}

/// The app's name and what it is, at the top of the page.
class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 16, SettingsLayout.gutter, 8),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.terminal, color: colors.onAccent, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AboutFacts.appName, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const HelpText(AboutFacts.description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One built-in theme: its colours, name and where they come from.
class _ThemeCredit extends StatelessWidget {
  const _ThemeCredit({required this.theme});

  final ThemeSpec theme;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(theme.name),
        subtitle: Text(theme.credit ?? AboutFacts.appName),
        trailing: SizedBox(width: 104, child: ThemeSwatches(theme: theme, size: 8)),
      );
}
