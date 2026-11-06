import 'package:flutter/material.dart';

import '../../app/app_icons.dart';
import '../../app/app_scope.dart';
import '../../data/app_settings.dart';

/// The overflow menu of the terminal screen.
class TerminalMenu extends StatelessWidget {
  const TerminalMenu({
    super.key,
    required this.onNewTerminal,
    required this.onTunnels,
    required this.onCommandHistory,
    required this.onFind,
    required this.onPaste,
    required this.onCopyScreen,
    required this.onBigger,
    required this.onSmaller,
    required this.onClearHistory,
    required this.recording,
    required this.onRecord,
    required this.onSwitchTheme,
    required this.onNextBackground,
    required this.onClose,
    required this.onDisconnect,
  });

  final VoidCallback onNewTerminal, onTunnels, onCommandHistory, onFind, onPaste, onCopyScreen, onBigger, onSmaller, onClearHistory, onSwitchTheme, onClose, onDisconnect;
  final VoidCallback onRecord;
  final bool recording;

  /// Null when the theme has fewer than two pictures to move between.
  final VoidCallback? onNextBackground;

  @override
  Widget build(BuildContext context) {
    final size = AppScope.store(context).settings.fontSize;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'More',
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: onNewTerminal,
          child: const ListTile(leading: Icon(Icons.add), title: Text('New terminal')),
        ),
        PopupMenuItem(
          value: onTunnels,
          child: const ListTile(leading: Icon(Icons.swap_horiz), title: Text('Tunnels')),
        ),
        PopupMenuItem(
          value: onCommandHistory,
          child: const ListTile(leading: Icon(Icons.history), title: Text('Command history')),
        ),
        PopupMenuItem(
          value: onFind,
          child: const ListTile(leading: Icon(Icons.search), title: Text('Find')),
        ),
        PopupMenuItem(
          value: onPaste,
          child: const ListTile(leading: Icon(Icons.content_paste), title: Text('Paste')),
        ),
        PopupMenuItem(
          value: onCopyScreen,
          child: const ListTile(leading: Icon(Icons.copy_all), title: Text('Copy screen text')),
        ),
        PopupMenuItem(
          value: onBigger,
          enabled: size < AppSettings.maxFontSize,
          child: ListTile(leading: const Icon(Icons.text_increase), title: Text('Bigger text (${size.round()})')),
        ),
        PopupMenuItem(
          value: onSmaller,
          enabled: size > AppSettings.minFontSize,
          child: const ListTile(leading: Icon(Icons.text_decrease), title: Text('Smaller text')),
        ),
        PopupMenuItem(
          value: onClearHistory,
          child: const ListTile(leading: Icon(Icons.clear_all), title: Text('Clear scrollback')),
        ),
        PopupMenuItem(
          value: onRecord,
          child: ListTile(
            leading: Icon(recording ? Icons.stop_circle_outlined : Icons.fiber_manual_record_outlined),
            title: Text(recording ? 'Stop recording' : 'Record'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: onSwitchTheme,
          child: const ListTile(leading: AppIcon(AppIcons.palette), title: Text('Switch theme')),
        ),
        if (onNextBackground != null)
          PopupMenuItem(
            value: onNextBackground,
            child: const ListTile(leading: AppIcon(AppIcons.image), title: Text('Next background')),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: onClose,
          child: const ListTile(leading: Icon(Icons.close), title: Text('Close terminal')),
        ),
        PopupMenuItem(
          value: onDisconnect,
          child: const ListTile(leading: Icon(Icons.link_off), title: Text('Disconnect')),
        ),
      ],
    );
  }
}
