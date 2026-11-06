import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import 'server_stats.dart';
import 'server_status_controller.dart';

/// A card with a server's CPU, memory, disk, load and uptime, redrawn
/// whenever [controller] reads new numbers.
class ServerStatusCard extends StatelessWidget {
  const ServerStatusCard({super.key, required this.host, required this.controller});

  final Host host;
  final ServerStatusController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(host.title, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        MonoText(host.target, style: text.bodySmall?.copyWith(color: colors.muted), maxLines: 1),
                      ],
                    ),
                  ),
                  if (controller.running && controller.phase != StatusPhase.unsupported)
                    Tooltip(
                      message: 'Updates every ${controller.every.inSeconds} seconds',
                      child: StatusDot(live: controller.phase == StatusPhase.ready, size: 10),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ..._body(context, colors),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AppColors colors) {
    final stats = controller.stats;
    switch (controller.phase) {
      case StatusPhase.loading:
        return const [
          Center(
            child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
          ),
          Text('Reading the numbers…', textAlign: TextAlign.center),
        ];
      case StatusPhase.unsupported:
        return [
          Icon(Icons.info_outline, color: colors.muted),
          const SizedBox(height: 8),
          const Text('Status is not available for this server. It works on Linux servers, which have /proc.', textAlign: TextAlign.center),
        ];
      case StatusPhase.failed when stats == null:
        return [
          Icon(Icons.error_outline, color: colors.danger),
          const SizedBox(height: 8),
          Text('Could not read the status: ${controller.error}', textAlign: TextAlign.center),
        ];
      case StatusPhase.failed:
      case StatusPhase.ready:
        final s = stats!;
        return [
          _Meter(
            label: 'CPU',
            value: s.cpuPercent == null ? 'Unknown' : '${s.cpuPercent!.round()} %',
            fraction: s.cpuPercent == null ? null : s.cpuPercent! / 100,
          ),
          _Meter(label: 'Memory', value: '${StatsFormat.kib(s.memUsedKb)} of ${StatsFormat.kib(s.memTotalKb)}', fraction: s.memFraction),
          _Meter(
            label: 'Disk /',
            value: s.diskTotalKb == 0 ? 'Unknown' : '${StatsFormat.kib(s.diskUsedKb)} of ${StatsFormat.kib(s.diskTotalKb)}',
            fraction: s.diskFraction,
          ),
          _Fact(label: 'Load', value: s.load.isEmpty ? 'Unknown' : StatsFormat.load(s.load), hint: '1, 5 and 15 minutes'),
          _Fact(label: 'Up for', value: s.uptime == null ? 'Unknown' : StatsFormat.uptime(s.uptime!)),
          if (controller.phase == StatusPhase.failed) ...[
            const SizedBox(height: 8),
            Text('The last update failed: ${controller.error}', style: TextStyle(color: colors.danger)),
          ],
        ];
    }
  }
}

/// A label, a value and a bar that turns the danger colour past 90 %.
class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value, required this.fraction});

  final String label;
  final String value;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final f = fraction;
    final percent = f == null ? '' : ', ${(f * 100).round()} percent';
    return Semantics(
      container: true,
      label: '$label: $value$percent',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Flexible(
                  child: Text(value, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: f ?? 0,
                minHeight: 8,
                color: (f ?? 0) > 0.9 ? colors.danger : colors.accent,
                backgroundColor: colors.raised,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label and a value on one line.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          MonoText(value),
        ],
      ),
    );
    return hint == null ? row : Tooltip(message: hint, child: row);
  }
}
