import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A clear strip over the terminal while broadcast mode is on, so the
/// user never forgets that typing goes to several servers.
class BroadcastBanner extends StatelessWidget {
  const BroadcastBanner({super.key, required this.count, required this.onStop});

  /// Terminals that get the typing, this one included.
  final int count;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Material(
      color: colors.accent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
        child: Row(
          children: [
            Icon(Icons.podcasts, size: 18, color: colors.onAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Typing to $count terminals',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.onAccent),
                ),
              ),
            ),
            TextButton(
              onPressed: onStop,
              style: TextButton.styleFrom(foregroundColor: colors.onAccent, minimumSize: const Size(64, 44)),
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}
