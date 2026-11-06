import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/theme.dart';
import '../../data/app_settings.dart';

/// Shown above the keyboard while a dropped connection is being
/// restored. The terminal keeps its screen; typing waits until it is back.
class ReconnectBanner extends StatelessWidget {
  const ReconnectBanner({super.key, required this.note, required this.onTryNow, required this.onStop});

  final String note;
  final VoidCallback onTryNow;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    // A still icon when motion is off (setting or system).
    final still = AppMotion.of(context).speed == MotionSpeed.off;
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 18,
                child: still ? Icon(Icons.sync, size: 18, color: colors.accent) : CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Semantics(liveRegion: true, child: Text(note))),
              TextButton(onPressed: onStop, child: const Text('Stop')),
              TextButton(onPressed: onTryNow, child: const Text('Try now')),
            ],
          ),
        ),
      ),
    );
  }
}
