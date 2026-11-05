import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../../src/rust/api/tunnel_types.dart';

/// Creates or edits a saved tunnel in a bottom sheet.
class TunnelEditorSheet extends StatefulWidget {
  const TunnelEditorSheet({super.key, required this.hostId, this.rule});

  final String hostId;
  final ForwardRule? rule;

  static Future<void> show(BuildContext context, {required String hostId, ForwardRule? rule}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TunnelEditorSheet(hostId: hostId, rule: rule),
    );
  }

  @override
  State<TunnelEditorSheet> createState() => _TunnelEditorSheetState();
}

class _TunnelEditorSheetState extends State<TunnelEditorSheet> {
  final _form = GlobalKey<FormState>();
  late TunnelKind _kind = widget.rule?.kind ?? TunnelKind.local;
  late final _label = TextEditingController(text: widget.rule?.label ?? '');
  late final _bindHost = TextEditingController(text: widget.rule?.bindHost ?? '127.0.0.1');
  late final _bindPort = TextEditingController(text: widget.rule == null ? '' : '${widget.rule!.bindPort}');
  late final _targetHost = TextEditingController(text: widget.rule?.targetHost ?? '127.0.0.1');
  late final _targetPort = TextEditingController(text: widget.rule == null || widget.rule!.targetPort == 0 ? '' : '${widget.rule!.targetPort}');

  @override
  void dispose() {
    for (final c in [_label, _bindHost, _bindPort, _targetHost, _targetPort]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final rule = ForwardRule(
      id: widget.rule?.id ?? VaultStore.newId(),
      hostId: widget.hostId,
      kind: _kind,
      label: _label.text.trim(),
      bindHost: _bindHost.text.trim(),
      bindPort: int.parse(_bindPort.text.trim()),
      targetHost: _kind == TunnelKind.dynamic_ ? '' : _targetHost.text.trim(),
      targetPort: _kind == TunnelKind.dynamic_ ? 0 : int.parse(_targetPort.text.trim()),
    );
    AppScope.store(context).saveForward(rule);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final needsTarget = _kind != TunnelKind.dynamic_;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.rule == null ? 'New tunnel' : 'Edit tunnel', style: text.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<TunnelKind>(
                segments: const [
                  ButtonSegment(value: TunnelKind.local, label: Text('Local')),
                  ButtonSegment(value: TunnelKind.remote, label: Text('Remote')),
                  ButtonSegment(value: TunnelKind.dynamic_, label: Text('SOCKS5')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 8),
              Text(_TunnelHelp.of(_kind), style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'Database'),
              ),
              const SizedBox(height: 12),
              _HostPortRow(
                hostLabel: _kind == TunnelKind.remote ? 'Listen on server address' : 'Listen on address',
                portLabel: 'Port',
                host: _bindHost,
                port: _bindPort,
                allowZero: true,
              ),
              if (needsTarget) ...[
                const SizedBox(height: 12),
                _HostPortRow(
                  hostLabel: _kind == TunnelKind.remote ? 'Send to address (this side)' : 'Send to address (server side)',
                  portLabel: 'Port',
                  host: _targetHost,
                  port: _targetPort,
                  allowZero: false,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: const Text('Save tunnel')),
            ],
          ),
        ),
      ),
    );
  }
}

/// An address field and a port field side by side.
class _HostPortRow extends StatelessWidget {
  const _HostPortRow({required this.hostLabel, required this.portLabel, required this.host, required this.port, required this.allowZero});

  final String hostLabel;
  final String portLabel;
  final TextEditingController host;
  final TextEditingController port;

  /// Port 0 means "pick any free port".
  final bool allowZero;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: host,
            decoration: InputDecoration(labelText: hostLabel),
            autocorrect: false,
            keyboardType: TextInputType.url,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an address' : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: port,
            decoration: InputDecoration(labelText: portLabel, helperText: allowZero ? '0 = any free port' : null),
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              if (n == null || n < (allowZero ? 0 : 1) || n > 65535) return allowZero ? '0 to 65535' : '1 to 65535';
              return null;
            },
          ),
        ),
      ],
    );
  }
}

abstract final class _TunnelHelp {
  static String of(TunnelKind kind) => switch (kind) {
    TunnelKind.local => 'A port on this device leads to an address the server can reach, like ssh -L.',
    TunnelKind.remote => 'A port on the server leads to an address this device can reach, like ssh -R.',
    TunnelKind.dynamic_ => 'A SOCKS5 proxy on this device sends app traffic through the server, like ssh -D.',
  };
}
