import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Replaces the key bar once the shell has ended.
class EndedBanner extends StatelessWidget {
  const EndedBanner({super.key, required this.reason, required this.onReconnect, required this.onClose});

  final String reason;
  final VoidCallback onReconnect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colors.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(reason)),
              TextButton(onPressed: onClose, child: const Text('Close')),
              FilledButton(onPressed: onReconnect, child: const Text('Reconnect')),
            ],
          ),
        ),
      ),
    );
  }
}
