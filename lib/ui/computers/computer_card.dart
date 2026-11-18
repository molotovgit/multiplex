import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../data/models.dart';
import '../../sessions/tailscale_node.dart';
import '../common/widgets.dart';
import '../files/files_screen.dart';
import '../hosts/host_connector.dart';
import 'computer_screen.dart';
import 'computer_status.dart';
import 'panel_screen.dart';

/// A paired computer on Home: its name and state, one big button for the
/// thing done most (the desktop), and the next most used a tap away.
class ComputerCard extends StatelessWidget {
  const ComputerCard({super.key, required this.host});

  final Host host;

  static Future<void> openFiles(BuildContext context, Host host) async {
    final session = await HostConnector.connect(context, host);
    if (session != null && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FilesScreen(session: session)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([AppScope.sessions(context), TailscaleNode.instance]),
      builder: (context, _) {
        final status = ComputerStatus.of(context, host);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Material(
            color: look.surfaces.card,
            elevation: look.surfaces.elevation,
            shadowColor: look.surfaces.shadow,
            shape: look.shapes.border(look.shapes.card, look.surfaces.side),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => ComputerScreen.open(context, host),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.computer, color: colors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(host.title, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  StatusDot(live: status.live),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      status.label,
                                      style: text.bodySmall?.copyWith(color: colors.muted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Everything ${host.title} can do',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => ComputerScreen.open(context, host),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => HostConnector.openDesktop(context, host),
                              icon: const Icon(Icons.desktop_windows_outlined),
                              label: const Text('Desktop'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Terminal',
                            icon: const Icon(Icons.terminal),
                            onPressed: () => HostConnector.openTerminal(context, host),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(tooltip: 'Files', icon: const Icon(Icons.folder_outlined), onPressed: () => openFiles(context, host)),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'Panel',
                            icon: const Icon(Icons.space_dashboard_outlined),
                            onPressed: () => PanelScreen.open(context, host),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
