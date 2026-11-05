import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/tunnel_types.dart';
import '../common/widgets.dart';
import '../hosts/host_connector.dart';
import 'tunnel_editor_sheet.dart';

/// The saved port forwards of one host. Each can be switched on and off;
/// running ones show live traffic numbers.
class TunnelsScreen extends StatelessWidget {
  const TunnelsScreen({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    final sessions = AppScope.sessions(context);
    return Scaffold(
      appBar: AppBar(title: Text('Tunnels on ${host.title}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TunnelEditorSheet.show(context, hostId: host.id),
        icon: const Icon(Icons.add),
        label: const Text('New tunnel'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, sessions]),
        builder: (context, _) {
          final rules = store.forwardsFor(host.id);
          if (rules.isEmpty) {
            return EmptyState(
              icon: Icons.swap_horiz,
              title: 'No tunnels yet',
              message:
                  'A tunnel forwards a port through this server, for example to open a database or a web page '
                  'that only the server can reach.',
              actionLabel: 'Create a tunnel',
              onAction: () => TunnelEditorSheet.show(context, hostId: host.id),
            );
          }
          final session = sessions.sessionFor(host.id);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: rules.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _TunnelCard(host: host, rule: rules[i], session: session),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One tunnel: what it forwards, a switch to run it, and its traffic.
class _TunnelCard extends StatefulWidget {
  const _TunnelCard({required this.host, required this.rule, required this.session});

  final Host host;
  final ForwardRule rule;
  final LiveSession? session;

  @override
  State<_TunnelCard> createState() => _TunnelCardState();
}

class _TunnelCardState extends State<_TunnelCard> {
  bool _busy = false;

  RunningTunnel? get _running {
    final running = widget.session?.tunnelFor(widget.rule.id);
    return running != null && running.tunnel.isRunning() ? running : null;
  }

  Future<void> _toggle(bool on) async {
    final sessions = AppScope.sessions(context);
    setState(() => _busy = true);
    try {
      if (on) {
        final session = widget.session ?? await HostConnector.connect(context, widget.host);
        if (session == null) return;
        final started = await sessions.startTunnel(session, widget.rule);
        if (mounted) Toast.show(context, _TunnelText.startedMessage(widget.rule, started.tunnel.boundPort()));
      } else if (_running != null && widget.session != null) {
        await sessions.stopTunnel(widget.session!, _running!);
      }
    } catch (e) {
      if (mounted) Toast.show(context, 'The tunnel could not start: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await Confirm.ask(context, title: 'Delete this tunnel?', message: widget.rule.summary, action: 'Delete tunnel');
    if (!ok || !mounted) return;
    final running = _running;
    if (running != null && widget.session != null) await AppScope.sessions(context).stopTunnel(widget.session!, running);
    if (mounted) AppScope.store(context).deleteForward(widget.rule.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final running = _running;
    final title = widget.rule.label.isEmpty ? _TunnelText.kindName(widget.rule.kind) : widget.rule.label;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusDot(live: running != null),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: text.titleMedium)),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                else
                  Switch(value: running != null, onChanged: _toggle),
                _TunnelMenu(
                  onEdit: () => TunnelEditorSheet.show(context, hostId: widget.host.id, rule: widget.rule),
                  onDelete: _delete,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: MonoText(widget.rule.summary, style: text.bodyMedium?.copyWith(color: colors.muted)),
            ),
            if (running != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: _TunnelStats(running: running),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TunnelStats extends StatelessWidget {
  const _TunnelStats({required this.running});

  final RunningTunnel running;

  @override
  Widget build(BuildContext context) {
    final stats = running.tunnel.stats();
    final port = running.tunnel.boundPort();
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColorsTheme.of(context).muted);
    return Text(
      'Listening on port $port. ${stats.connectionsActive} open, ${stats.connectionsTotal} total, '
      '${_TunnelText.bytes(stats.bytesSent)} sent, ${_TunnelText.bytes(stats.bytesReceived)} received',
      style: style,
    );
  }
}

class _TunnelMenu extends StatelessWidget {
  const _TunnelMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Tunnel actions',
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: onEdit,
          child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
        ),
        PopupMenuItem(
          value: onDelete,
          child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
      ],
    );
  }
}

/// Wording shared by the tunnel screens.
abstract final class _TunnelText {
  static String kindName(TunnelKind kind) => switch (kind) {
    TunnelKind.local => 'Local forward',
    TunnelKind.remote => 'Remote forward',
    TunnelKind.dynamic_ => 'SOCKS5 proxy',
  };

  static String startedMessage(ForwardRule rule, int port) => switch (rule.kind) {
    TunnelKind.local => 'Open ${rule.bindHost}:$port on this device to reach ${rule.targetHost}:${rule.targetPort}',
    TunnelKind.remote => 'The server now forwards port $port to ${rule.targetHost}:${rule.targetPort}',
    TunnelKind.dynamic_ => 'SOCKS5 proxy running on ${rule.bindHost}:$port',
  };

  static String bytes(BigInt value) {
    final n = value.toDouble();
    if (n < 1024) return '${value.toInt()} B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
