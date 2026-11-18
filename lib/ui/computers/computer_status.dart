import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../../sessions/tailscale_node.dart';

/// What can be said about a paired computer right now, without probing it:
/// an open connection, or what the tailnet knows.
class ComputerStatus {
  const ComputerStatus(this.label, {required this.live});

  final String label;

  /// Reachable as far as we know (drawn with the "live" colour).
  final bool live;

  static ComputerStatus of(BuildContext context, Host host) {
    final session = AppScope.sessions(context).sessionFor(host.id);
    if (session != null) {
      return ComputerStatus(session.ssh.info().via == 'Tailscale' ? 'Connected · Tailscale' : 'Connected · home network', live: true);
    }
    final hasTailnet = host.viaTailscale || (host.tailscaleName ?? '').isNotEmpty;
    final node = TailscaleNode.instance;
    if (hasTailnet && node.running) {
      final device = node.deviceFor(host.tailnetName);
      if (device != null && device.online) return const ComputerStatus('Online · reachable from anywhere', live: true);
      if (device != null) return ComputerStatus(host.viaTailscale ? 'Offline' : 'Not on Tailscale now · home network only', live: false);
    }
    if (hasTailnet && node.needsLogin) return const ComputerStatus('Home network · sign in to Tailscale to reach it from anywhere', live: false);
    return ComputerStatus(host.viaTailscale ? 'Over Tailscale' : 'On your home network', live: false);
  }
}
