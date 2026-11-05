import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_spec.dart';
import '../../data/app_settings.dart';
import '../appearance/appearance_screen.dart';
import '../common/widgets.dart';
import 'about_screen.dart';
import 'app_lock_setup.dart';
import 'backup_screen.dart';
import '../keyboard/keyboard_settings_screen.dart';
import 'key_bar_editor_screen.dart';
import 'key_bar_layout.dart';
import 'settings_widgets.dart';

/// The fixed choices offered for terminal settings.
abstract final class TerminalChoices {
  static const scrollback = [
    ChoiceOption(1000, '1,000 lines'),
    ChoiceOption(5000, '5,000 lines'),
    ChoiceOption(10000, '10,000 lines'),
    ChoiceOption(50000, '50,000 lines'),
  ];

  static const keepAlive = [
    ChoiceOption(0, 'Off'),
    ChoiceOption(15, 'Every 15 seconds'),
    ChoiceOption(30, 'Every 30 seconds'),
    ChoiceOption(60, 'Every 60 seconds'),
  ];

  static String scrollbackLabel(int lines) => '${SettingsFormat.thousands(lines)} lines';

  static String keepAliveLabel(int secs) => secs <= 0 ? 'Off' : 'Every ${SettingsFormat.thousands(secs)} seconds';
}

/// App settings, in sections. Every change is saved straight away.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.unlock = const DeviceUnlock()});

  /// Used by the app lock switch; tests pass a fake.
  final DeviceUnlock unlock;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentWidth(
        child: ListenableBuilder(
          listenable: store,
          // Each section gets the values it shows, so it redraws when
          // they change.
          builder: (context, _) => ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _AppearanceSection(theme: store.activeTheme),
              _TerminalSection(settings: store.settings),
              _KeyboardSection(layout: KeyBarLayout(store.settings.keyBar)),
              _SecuritySection(unlock: unlock, on: store.settings.appLock),
              const _BackupSection(),
              const _ConnectionsSection(),
              const _AboutSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [screen] on top of settings.
abstract final class SettingsNavigation {
  static Future<void> open(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

/// The current theme, with its colours, opening the appearance screen.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.theme});

  final ThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Appearance'),
        // The swatches are hidden from screen readers; the tile reads as
        // "Theme: <name>" and stays tappable for them.
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(theme.name, semanticsLabel: 'Theme: ${theme.name}'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ThemeSwatches(theme: theme),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => SettingsNavigation.open(context, const AppearanceScreen()),
        ),
      ],
    );
  }
}

/// Scrollback, bold colours, keep-alive and keeping the screen on.
class _TerminalSection extends StatelessWidget {
  const _TerminalSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    void save(AppSettings next) => store.updateSettings(next);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Terminal'),
        ChoiceTile<int>(
          icon: Icons.history,
          title: 'Scrollback',
          description: 'How many lines you can scroll back through. Applies to terminals you open from now on.',
          value: settings.scrollbackLines,
          options: TerminalChoices.scrollback,
          fallbackLabel: TerminalChoices.scrollbackLabel,
          onChanged: (lines) => save(settings.copyWith(scrollbackLines: lines)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.format_bold),
          title: const Text('Bold text in bright colours'),
          subtitle: const Text('Like many classic terminals'),
          value: settings.boldIsBright,
          onChanged: (on) {
            save(settings.copyWith(boldIsBright: on));
            AppScope.sessions(context).applyTerminalTheme();
          },
        ),
        ChoiceTile<int>(
          icon: Icons.timer_outlined,
          title: 'Keep-alive',
          description:
              'Sends a small signal when the connection is quiet, so routers and servers do not drop it. '
              'Applies to connections you open from now on.',
          value: settings.keepAliveSecs,
          options: TerminalChoices.keepAlive,
          fallbackLabel: TerminalChoices.keepAliveLabel,
          onChanged: (secs) => save(settings.copyWith(keepAliveSecs: secs)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.light_mode_outlined),
          title: const Text('Keep the screen on'),
          subtitle: const Text('While a terminal is open'),
          value: settings.keepScreenOn,
          onChanged: (on) => save(settings.copyWith(keepScreenOn: on)),
        ),
      ],
    );
  }
}

/// The key bar above the on-screen keyboard.
class _KeyboardSection extends StatelessWidget {
  const _KeyboardSection({required this.layout});

  final KeyBarLayout layout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Keyboard'),
        ListTile(
          leading: const Icon(Icons.keyboard_outlined),
          title: const Text('Key bar'),
          subtitle: Text(layout.summary),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => SettingsNavigation.open(context, const KeyBarEditorScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.keyboard_alt_outlined),
          title: const Text('Terminal keyboard'),
          subtitle: const Text('Built-in keyboard, layout, size and feel'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => SettingsNavigation.open(context, const KeyboardSettingsScreen()),
        ),
      ],
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({required this.unlock, required this.on});

  final DeviceUnlock unlock;
  final bool on;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader('Security'),
      AppLockSwitch(unlock: unlock, on: on),
    ],
  );
}

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader('Backup & restore'),
      ListTile(
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Backup & restore'),
        subtitle: const Text('Save everything to an encrypted file, or bring a backup back'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => SettingsNavigation.open(context, const BackupScreen()),
      ),
    ],
  );
}

/// Shown only while connections are open: closes them all. It is in its
/// own section and in the danger colour, because it stops running work.
class _ConnectionsSection extends StatefulWidget {
  const _ConnectionsSection();

  @override
  State<_ConnectionsSection> createState() => _ConnectionsSectionState();
}

class _ConnectionsSectionState extends State<_ConnectionsSection> {
  /// True while connections are closing, which can take a moment.
  bool _closing = false;

  Future<void> _disconnectAll(int count) async {
    final sessions = AppScope.sessions(context);
    final ok = await Confirm.ask(
      context,
      title: 'Disconnect all?',
      message:
          'This closes ${SettingsFormat.count(count, 'connection', 'connections')} '
          'with their terminals and tunnels. Anything running in those terminals stops.',
      action: 'Disconnect all',
    );
    if (!ok || !mounted) return;
    setState(() => _closing = true);
    try {
      await sessions.disconnectAll();
    } finally {
      if (mounted) setState(() => _closing = false);
    }
    if (mounted) Toast.show(context, 'All connections are closed');
  }

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.sessions(context);
    final danger = AppColorsTheme.of(context).danger;
    // Only this part follows the connections, so the rest of the list
    // does not redraw on every connection check.
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final count = sessions.activeCount;
        if (count == 0) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Connections'),
            ListTile(
              iconColor: danger,
              textColor: danger,
              leading: const Icon(Icons.link_off),
              title: const Text('Disconnect all'),
              subtitle: Text(_closing ? 'Closing connections...' : '${SettingsFormat.count(count, 'connection', 'connections')} open'),
              trailing: _closing ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: _closing ? null : () => _disconnectAll(count),
            ),
          ],
        );
      },
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeader('About'),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('About Multiplex'),
        subtitle: const Text('Version, source code, licences and theme credits'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => SettingsNavigation.open(context, const AboutScreen()),
      ),
    ],
  );
}
