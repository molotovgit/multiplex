import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../common/widgets.dart';
import 'remote_paths.dart';

/// The current folder as tappable steps ("/ › home › ann"), plus a button
/// to type a path. Long paths scroll sideways and keep the end in view.
class PathBar extends StatefulWidget {
  const PathBar({super.key, required this.path, required this.onOpen, required this.onGoTo, this.enabled = true});

  final String path;
  final ValueChanged<String> onOpen;
  final VoidCallback onGoTo;
  final bool enabled;

  @override
  State<PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<PathBar> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _showEnd();
  }

  @override
  void didUpdateWidget(PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _showEnd();
  }

  /// Scrolls to the deepest folder once the new steps are laid out.
  void _showEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final segments = RemotePaths.segments(widget.path);
    return Container(
      height: 56,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outline))),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'Current folder ${widget.path}',
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: segments.length,
                separatorBuilder: (_, _) => Icon(Icons.chevron_right, size: 16, color: colors.muted),
                itemBuilder: (context, i) => _PathStep(
                  segment: segments[i],
                  current: i == segments.length - 1,
                  onOpen: widget.enabled ? widget.onOpen : null,
                ),
              ),
            ),
          ),
          IconButton(tooltip: 'Go to folder', icon: const Icon(Icons.edit_outlined), onPressed: widget.enabled ? widget.onGoTo : null),
        ],
      ),
    );
  }
}

/// One step of the path. The last step is where the user is, so it is
/// shown bold and does nothing when tapped.
class _PathStep extends StatelessWidget {
  const _PathStep({required this.segment, required this.current, required this.onOpen});

  final PathSegment segment;
  final bool current;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    if (current) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: MonoText(segment.label, style: style?.copyWith(color: colors.text, fontWeight: FontWeight.w600)),
        ),
      );
    }
    final open = onOpen;
    return Center(
      child: TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 8)),
        onPressed: open == null ? null : () => open(segment.path),
        child: MonoText(segment.label, style: style?.copyWith(color: open == null ? colors.muted : colors.accent)),
      ),
    );
  }
}
