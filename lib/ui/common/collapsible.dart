import 'package:flutter/material.dart';

/// Folds [child] away to nothing when [open] is false, sliding it shut
/// toward [from], and unfolds it again when it is true. Instant when the
/// system asks for less motion.
class Collapsible extends StatelessWidget {
  const Collapsible({super.key, required this.open, required this.child, this.from = Alignment.bottomCenter});

  final bool open;
  final Widget child;
  final Alignment from;

  static const duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedAlign(
      alignment: from,
      heightFactor: open ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      child: ExcludeFocus(
        excluding: !open,
        child: ExcludeSemantics(excluding: !open, child: child),
      ),
    ),
  );
}
