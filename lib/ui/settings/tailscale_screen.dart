import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../../sessions/tailscale_node.dart';
import '../../src/rust/api/tailscale_types.dart';
import '../common/widgets.dart';
import '../hosts/host_connector.dart';
import '../hosts/host_editor_screen.dart';
import 'settings_widgets.dart';

/// Tailscale, built into Multiplex: sign in once, then reach your devices
/// from anywhere (no VPN app needed). Shows each device and whether the
/// phone reaches it directly (fastest) or through a Tailscale relay.
class TailscaleScreen extends StatefulWidget {
  const TailscaleScreen({super.key});

  @override
  State<TailscaleScreen> createState() => _TailscaleScreenState();
}

class _TailscaleScreenState extends State<TailscaleScreen> {
  final node = TailscaleNode.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    node.addListener(_changed);
    node.watch();
    if (node.available) node.ensureStarted().ignore();
  }

  @override
  void dispose() {
    node.removeListener(_changed);
    node.unwatch();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final url = await node.startSignIn();
      if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) Toast.show(context, 'Could not start signing in: ${TailscaleNode.clean(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await Confirm.ask(
      context,
      title: 'Sign out of Tailscale?',
      message: 'Hosts that connect through Tailscale stop working on this phone until you sign in again.',
      action: 'Sign out',
    );
    if (!ok) return;
    await node.signOut();
  }

  void _addHost(TailscaleDevice device) {
    final store = AppScope.store(context);
    final existing = store.hosts.where((h) => h.viaTailscale && (h.address == device.name || h.address == device.dnsName)).firstOrNull;
    final draft = existing ?? Host(id: VaultStore.newId(), label: device.name, address: device.name, viaTailscale: true, authMode: AuthMode.key);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostEditorScreen(host: existing, draft: existing == null ? draft : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final st = node.status;
    final devices = [...?st?.devices]..sort((a, b) => (b.online ? 1 : 0) - (a.online ? 1 : 0));
    return Scaffold(
      appBar: AppBar(title: const Text('Tailscale')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(SettingsLayout.gutter),
          children: [
            if (!node.available)
              const NoticeBox(tone: NoticeTone.warning, text: 'This build of Multiplex does not include Tailscale.')
            else ...[
              _StatusCard(node: node, busy: _busy, onSignIn: _signIn, onSignOut: _signOut),
              if (node.problem != null) ...[const SizedBox(height: 12), NoticeBox(tone: NoticeTone.error, text: node.problem!)],
              if (node.running) ...[
                const SectionHeader('Your devices'),
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No other devices on this tailnet yet.', style: text.bodyMedium?.copyWith(color: colors.muted)),
                  ),
                for (final d in devices) _DeviceTile(device: d, onAdd: () => _addHost(d), onDesktop: () => _openDesktop(d)),
                const SizedBox(height: 8),
                const HelpText(
                  'Direct means the phone talks to the device peer to peer, the fastest way. '
                  'Relay means a Tailscale server passes the traffic on, which adds delay; '
                  'it turns direct by itself when the networks allow it.',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDesktop(TailscaleDevice device) async {
    final store = AppScope.store(context);
    final host = store.hosts.where((h) => h.viaTailscale && (h.address == device.name || h.address == device.dnsName)).firstOrNull;
    if (host == null) {
      _addHost(device);
      return;
    }
    await HostConnector.openDesktop(context, host);
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.node, required this.busy, required this.onSignIn, required this.onSignOut});

  final TailscaleNode node;
  final bool busy;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final st = node.status;
    final me = st?.thisDevice;
    final (title, detail) = switch (st?.state) {
      'Running' => ('Connected', [if (st!.user.isNotEmpty) st.user, if (st.tailnet.isNotEmpty) st.tailnet].join(' · ')),
      'NeedsLogin' => ('Not signed in', 'Sign in with your Tailscale account to reach your devices from anywhere.'),
      'NeedsMachineAuth' => ('Waiting for approval', 'An admin of the tailnet has to approve this phone.'),
      'Starting' => ('Connecting…', ''),
      'Stopped' => ('Stopped', ''),
      _ => ('Starting…', ''),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusDot(live: node.running),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: text.titleMedium)),
              ],
            ),
            if (detail.isNotEmpty) ...[const SizedBox(height: 6), Text(detail, style: text.bodyMedium?.copyWith(color: colors.muted))],
            if (me != null && node.running) ...[
              const SizedBox(height: 6),
              MonoText('${me.name} · ${me.ips.firstOrNull ?? ''}', style: text.bodySmall?.copyWith(color: colors.muted)),
            ],
            const SizedBox(height: 14),
            if (node.running)
              OutlinedButton.icon(onPressed: onSignOut, icon: const Icon(Icons.logout), label: const Text('Sign out'))
            else
              FilledButton.icon(
                onPressed: busy ? null : onSignIn,
                icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                label: const Text('Sign in to Tailscale'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onAdd, required this.onDesktop});

  final TailscaleDevice device;
  final VoidCallback onAdd;
  final VoidCallback onDesktop;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final path = !device.online ? 'Offline' : (device.direct ? 'Direct' : (device.relay.isEmpty ? 'Not yet used' : 'Relay ${device.relay}'));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(device.os), color: device.online ? colors.text : colors.muted),
      title: Text(device.name),
      subtitle: Text('${device.ips.firstOrNull ?? ''} · ${device.os.isEmpty ? 'device' : device.os} · $path'),
      trailing: PopupMenuButton<int>(
        tooltip: 'Actions for ${device.name}',
        onSelected: (v) => v == 0 ? onDesktop() : onAdd(),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 0,
            child: ListTile(leading: Icon(Icons.desktop_windows_outlined), title: Text('Remote desktop')),
          ),
          PopupMenuItem(
            value: 1,
            child: ListTile(leading: Icon(Icons.add), title: Text('Add as host')),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String os) => switch (os.toLowerCase()) {
    'linux' => Icons.computer,
    'macos' => Icons.laptop_mac,
    'windows' => Icons.laptop_windows,
    'android' => Icons.phone_android,
    'ios' => Icons.phone_iphone,
    _ => Icons.devices_other,
  };
}
