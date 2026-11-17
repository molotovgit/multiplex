import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../data/models.dart';
import '../../sessions/error_text.dart';
import '../../sessions/tailscale_node.dart';
import '../../src/rust/api/wake.dart';
import '../common/widgets.dart';
import '../desktop/desktop_settings.dart';
import '../hosts/host_connector.dart';
import '../hosts/host_editor_screen.dart';
import '../hosts/server_status_screen.dart';
import '../settings/settings_widgets.dart';
import '../tunnels/tunnels_screen.dart';
import 'agents_screen.dart';
import 'computer_card.dart';
import 'computer_sharing_screen.dart';
import 'computer_status.dart';
import 'panel_screen.dart';
import 'screen_cast_screen.dart';
import 'touchpad_screen.dart';

/// Everything one paired computer can do, as a grid of tiles. New
/// features arrive as one more tile here.
class ComputerScreen extends StatelessWidget {
  const ComputerScreen({super.key, required this.hostId, this.wake});

  final String hostId;

  /// Sends the wake signal (network card address, home address). Tests pass a stand-in.
  final Future<void> Function(String mac, String? home)? wake;

  static Future<void> open(BuildContext context, Host host) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComputerScreen(hostId: host.id)));

  /// Sends the wake signal. Tests pass a stand-in for the sender.
  Future<void> _wake(BuildContext context, Host host) async {
    try {
      await (wake ?? ((String mac, String? home) => wakeOnLan(mac: mac, homeAddress: home)))(host.mac!, host.viaTailscale ? null : host.address);
      if (context.mounted) Toast.show(context, 'Wake signal sent to ${host.title}. It reaches the computer only on its home network.');
    } catch (e) {
      if (context.mounted) Toast.show(context, errorSentence(e, fallback: 'The wake signal could not be sent.'));
    }
  }

  Future<void> _remove(BuildContext context, Host host) async {
    final ok = await Confirm.ask(
      context,
      title: 'Remove ${host.title}?',
      message: 'It leaves this phone. On the computer, `multiplex unpair` removes this phone\'s access.',
      action: 'Remove',
    );
    if (!ok || !context.mounted) return;
    final sessions = AppScope.sessions(context);
    final open = sessions.sessionFor(host.id);
    if (open != null) await sessions.disconnect(open);
    if (!context.mounted) return;
    AppScope.store(context).deleteHost(host.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final host = store.host(hostId);
    if (host == null) return const Scaffold(body: SizedBox.shrink());
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final tiles = <_Tile>[
      _Tile(Icons.desktop_windows_outlined, 'Desktop', 'See and control the screen', () => HostConnector.openDesktop(context, host), primary: true),
      _Tile(Icons.space_dashboard_outlined, 'Panel', 'Workspaces, windows, media', () => PanelScreen.open(context, host)),
      _Tile(Icons.touch_app_outlined, 'Touchpad', 'Pointer and keys, no picture', () => TouchpadScreen.show(context, host)),
      _Tile(Icons.terminal, 'Terminal', 'A shell on the computer', () => HostConnector.openTerminal(context, host)),
      _Tile(Icons.folder_outlined, 'Files', 'Browse, send and fetch', () => ComputerCard.openFiles(context, host)),
      _Tile(
        Icons.add_to_queue_outlined,
        'Extend screen',
        'The phone as one more monitor',
        () => HostConnector.openDesktop(context, host, screen: DesktopScreenMode.fitted),
      ),
      _Tile(Icons.cast, 'Phone screen', 'Show this phone on the computer', () => ScreenCastScreen.show(context, host)),
      _Tile(Icons.videocam_outlined, 'Camera', 'This phone as a webcam', () => ScreenCastScreen.showCamera(context, host)),
      _Tile(Icons.mic_none, 'Microphone', 'This phone as a microphone', () => ScreenCastScreen.showMicrophone(context, host)),
      _Tile(Icons.smart_toy_outlined, 'Agents', 'Coding agents and what they do', () => AgentsScreen.show(context, host)),
      _Tile(Icons.swap_horiz, 'Tunnels', 'Forward ports', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TunnelsScreen(host: host)))),
      _Tile(Icons.monitor_heart_outlined, 'Status', 'Load, memory and disks', () => ServerStatusScreen.open(context, host)),
      // Wake-on-LAN, with the network card's address saved at pairing.
      if ((host.mac ?? '').isNotEmpty) _Tile(Icons.power_settings_new, 'Wake', 'Switch it on from the home network', () => _wake(context, host)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(host.title),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'More for ${host.title}',
            onSelected: (v) => switch (v) {
              0 => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostEditorScreen(host: host))),
              2 => ComputerSharingScreen.open(context, host.id),
              _ => _remove(context, host),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 2,
                child: ListTile(leading: Icon(Icons.sync_alt), title: Text('Sharing and notifications')),
              ),
              PopupMenuItem(
                value: 0,
                child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Connection details')),
              ),
              PopupMenuItem(
                value: 1,
                child: ListTile(leading: Icon(Icons.link_off), title: Text('Remove this computer')),
              ),
            ],
          ),
        ],
      ),
      body: ContentWidth(
        child: ListenableBuilder(
          listenable: Listenable.merge([AppScope.sessions(context), TailscaleNode.instance]),
          builder: (context, _) {
            final status = ComputerStatus.of(context, host);
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 8, SettingsLayout.gutter, 16),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        StatusDot(live: status.live),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(status.label, style: text.bodyMedium?.copyWith(color: colors.muted)),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 24),
                  // A fixed height, not a ratio: with three or four tiles in
                  // a row they get narrow, and a ratio would squeeze the text.
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 132,
                    ),
                    delegate: SliverChildListDelegate([for (final t in tiles) _TileCard(tile: t)]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.icon, this.title, this.subtitle, this.onTap, {this.primary = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// The thing done most: drawn in the accent colour.
  final bool primary;
}

class _TileCard extends StatelessWidget {
  const _TileCard({required this.tile});

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final text = Theme.of(context).textTheme;
    final fg = tile.primary ? colors.onAccent : colors.text;
    return Semantics(
      button: true,
      label: '${tile.title}: ${tile.subtitle}',
      child: Material(
        color: tile.primary ? colors.accent : look.surfaces.card,
        elevation: look.surfaces.elevation,
        shadowColor: look.surfaces.shadow,
        shape: look.shapes.border(look.shapes.card, tile.primary ? BorderSide.none : look.surfaces.side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tile.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tile.icon, color: tile.primary ? colors.onAccent : colors.accent, size: 28),
                const Spacer(),
                ExcludeSemantics(
                  child: Text(tile.title, style: text.titleSmall?.copyWith(color: fg)),
                ),
                const SizedBox(height: 2),
                ExcludeSemantics(
                  child: Text(
                    tile.subtitle,
                    style: text.bodySmall?.copyWith(color: tile.primary ? colors.onAccent.withValues(alpha: 0.85) : colors.muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
