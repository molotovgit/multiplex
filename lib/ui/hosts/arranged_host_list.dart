import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import 'host_arrangement.dart';
import 'host_tile.dart';

/// The hosts in the user's own order. Long-press a host and drag it to move
/// it; dropping it under another group's heading moves it into that group.
/// The host menu has Move up and Move down for doing the same without
/// dragging.
class ArrangedHostList extends StatelessWidget {
  const ArrangedHostList({super.key, required this.header, required this.groupMenu});

  /// Shown above the list and not draggable (search, recent hosts).
  final List<Widget> header;

  /// The menu next to a group's heading.
  final Widget Function(HostGroup group) groupMenu;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final arrangement = HostArrangement.of(store);
    return ReorderableListView.builder(
      // Only hosts can be dragged; headings are drop zones.
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 96),
      header: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: header),
      itemCount: arrangement.entries.length,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: (from, to) {
        final order = arrangement.afterMove(from, to);
        if (order != null) store.arrangeHosts(order);
      },
      proxyDecorator: (child, index, animation) => _DragShadow(animation: animation, child: child),
      itemBuilder: (context, index) => switch (arrangement.entries[index]) {
        GroupEntry(:final group, :final title, :final key) => KeyedSubtree(
          key: ValueKey(key),
          child: SectionHeader(title, trailing: group == null ? null : groupMenu(group)),
        ),
        HostEntry(:final host, :final key) => ReorderableDelayedDragStartListener(
          key: ValueKey(key),
          index: index,
          child: HostTile(host: host),
        ),
      },
    );
  }
}

/// Lifts the dragged host off the list with a soft shadow in the theme's
/// colours.
class _DragShadow extends StatelessWidget {
  const _DragShadow({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Material(
        elevation: 6 * animation.value,
        color: colors.raised,
        shadowColor: Color.lerp(colors.background, Colors.black, 0.6),
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
      child: child,
    );
  }
}
