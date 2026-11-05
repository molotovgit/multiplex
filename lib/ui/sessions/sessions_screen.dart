import '../../app/app_icons.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/session_manager.dart';
import '../common/widgets.dart';
import '../files/files_screen.dart';
import '../terminal/terminal_screen.dart';
import '../tunnels/tunnels_screen.dart';

/// Everything that is open right now: connections with their terminals
/// and tunnels.
class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.sessions(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: ListenableBuilder(
        listenable: sessions,
        builder: (context, _) {
          final open = sessions.sessions;
          if (open.isEmpty) {
            return const EmptyState(
              icon: Icons.terminal,
              title: 'Nothing open',
              message:
                  'Connect to a host from the Hosts list. Its terminals, file browser and tunnels show up here '
                  'and keep running while you switch screens.',
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: open.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _SessionCard(session: open[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final LiveSession session;

  void _open(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _disconnect(BuildContext context) async {
    final ok = await Confirm.ask(
      context,
      title: 'Disconnect from ${session.host.title}?',
      message: 'All terminals and tunnels on this connection will close.',
      action: 'Disconnect',
    );
    if (ok && context.mounted) await AppScope.sessions(context).disconnect(session);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final connected = session.connected;
    final since = TimeOfDay.fromDateTime(session.startedAt).format(context);
    final info = session.ssh.info();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusDot(live: connected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.host.title, style: text.titleMedium),
                      MonoText(
                        '${session.host.target}${info.via == null ? '' : '  via ${info.via}'}',
                        style: text.bodySmall?.copyWith(color: colors.muted),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                Text(connected ? 'Since $since' : 'Disconnected', style: text.bodySmall?.copyWith(color: connected ? colors.muted : colors.danger)),
              ],
            ),
            const SizedBox(height: 8),
            for (final terminal in session.terminals)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 20),
                leading: Icon(Icons.terminal, color: terminal.ended ? colors.muted : colors.accent),
                title: Text(terminal.title),
                subtitle: terminal.ended ? Text(terminal.endReason ?? '') : null,
                onTap: () => TerminalScreen.open(context, session, terminal),
              ),
            if (session.tunnels.isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 20),
                leading: Icon(Icons.swap_horiz, color: colors.live),
                title: Text(session.tunnels.length == 1 ? '1 tunnel running' : '${session.tunnels.length} tunnels running'),
                onTap: () => _open(context, TunnelsScreen(host: session.host)),
              ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => TerminalScreen.openNew(context, session),
                  icon: const Icon(Icons.add),
                  label: const Text('Terminal'),
                ),
                TextButton.icon(
                  onPressed: () => _open(context, FilesScreen(session: session)),
                  icon: const AppIcon(AppIcons.folder),
                  label: const Text('Files'),
                ),
                TextButton.icon(
                  onPressed: () => _open(context, TunnelsScreen(host: session.host)),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Tunnels'),
                ),
                TextButton.icon(
                  onPressed: () => _disconnect(context),
                  style: TextButton.styleFrom(foregroundColor: colors.danger),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
