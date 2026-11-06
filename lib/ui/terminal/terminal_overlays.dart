import 'package:flutter/material.dart';

/// Shown while scrolled back: how far back, and a way back to live output.
class JumpToLiveButton extends StatelessWidget {
  const JumpToLiveButton({super.key, required this.lines, required this.onPressed});

  final int lines;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: FloatingActionButton.extended(
        heroTag: null,
        onPressed: onPressed,
        icon: const Icon(Icons.vertical_align_bottom),
        label: Text('$lines lines up'),
      ),
    );
  }
}

/// Actions for the current selection.
class CopyBar extends StatelessWidget {
  const CopyBar({super.key, required this.onCopy, required this.onCancel});

  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(onPressed: onCopy, icon: const Icon(Icons.copy), label: const Text('Copy')),
              IconButton(tooltip: 'Clear selection', onPressed: onCancel, icon: const Icon(Icons.close)),
            ],
          ),
        ),
      ),
    );
  }
}
