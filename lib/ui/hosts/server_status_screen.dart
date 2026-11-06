import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../../sessions/session_manager.dart';
import '../common/widgets.dart';
import '../snippets/remote_runner.dart';
import 'host_connector.dart';
import 'server_status_card.dart';
import 'server_status_controller.dart';

/// A host's live status: CPU, memory, disk, load and uptime, read every
/// five seconds while this page is on screen and the app is in front.
///
/// An open connection to the host is reused. A connection opened just for
/// this page is closed again when the page closes, unless a terminal or a
/// tunnel was started on it meanwhile.
class ServerStatusScreen extends StatefulWidget {
  const ServerStatusScreen({super.key, required this.host});

  final Host host;

  static Future<void> open(BuildContext context, Host host) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ServerStatusScreen(host: host)));

  @override
  State<ServerStatusScreen> createState() => _ServerStatusScreenState();
}

class _ServerStatusScreenState extends State<ServerStatusScreen> {
  /// Each reading's output is tiny; this only guards against surprises.
  static const _maxBytes = 64 * 1024;

  late final SessionManager _sessions = AppScope.sessions(context);
  LiveSession? _session;
  LiveSession? _own;
  ServerStatusController? _status;
  AppLifecycleListener? _lifecycle;
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final reused = _sessions.sessionFor(widget.host.id) != null;
    final session = await HostConnector.connect(context, widget.host);
    if (!mounted) {
      if (session != null && !reused) _sessions.disconnect(session).ignore();
      return;
    }
    if (session == null) {
      Navigator.of(context).pop();
      return;
    }
    final status = ServerStatusController((command) async {
      try {
        return (await session.ssh.exec(command: command, maxBytes: _maxBytes)).stdout;
      } catch (error) {
        throw ErrorText.of(error);
      }
    }, isVisible: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true))..start();
    _lifecycle = AppLifecycleListener(onShow: status.start, onHide: status.stop);
    setState(() {
      _session = session;
      _own = reused ? null : session;
      _status = status;
      _connecting = false;
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _status?.dispose();
    final own = _own;
    if (own != null && own.terminals.isEmpty && own.tunnels.isEmpty) _sessions.disconnect(own).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server status'),
        actions: [
          if (status != null) IconButton(tooltip: 'Update now', icon: const Icon(Icons.refresh), onPressed: status.refresh),
          if (_session != null)
            IconButton(tooltip: 'Open terminal', icon: const Icon(Icons.terminal), onPressed: () => HostConnector.openTerminal(context, widget.host)),
        ],
      ),
      body: _connecting || status == null
          ? EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'Connecting to ${widget.host.title}',
              message: 'The status shows once the connection is open.',
            )
          : SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ServerStatusCard(host: widget.host, controller: status),
                ),
              ),
            ),
    );
  }
}
