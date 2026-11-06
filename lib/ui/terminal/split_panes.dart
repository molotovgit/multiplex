import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/terminal_controller.dart';
import 'split_controller.dart';

/// Builds the view of one terminal pane.
typedef TerminalPaneBuilder = Widget Function(TerminalController terminal, FocusNode focus);

/// One or two terminals side by side. With two, a divider between them
/// can be dragged, a touch on a pane makes it the one that types (it gets
/// an accent border), and the second pane has a close button.
class SplitPanes extends StatefulWidget {
  const SplitPanes({super.key, required this.split, required this.shown, required this.paneFor});

  final SplitController split;

  /// False while the screen is too narrow: only the first pane shows.
  final bool shown;
  final TerminalPaneBuilder paneFor;

  /// Finds the divider in tests.
  static const dividerKey = ValueKey('split-divider');

  @override
  State<SplitPanes> createState() => _SplitPanesState();
}

class _SplitPanesState extends State<SplitPanes> {
  /// The divider's touch area; the line drawn in it is thinner.
  static const _dividerWidth = 24.0;

  /// Arrow keys move the divider by this share of the width.
  static const _keyStep = 0.05;

  late final _sessions = AppScope.sessions(context);

  @override
  void initState() {
    super.initState();
    // A terminal closed from its own screen or the Sessions page must
    // not stay on screen here.
    _sessions.addListener(_dropClosed);
  }

  @override
  void dispose() {
    _sessions.removeListener(_dropClosed);
    super.dispose();
  }

  void _dropClosed() => widget.split.dropClosed(_sessions);

  @override
  Widget build(BuildContext context) {
    final split = widget.split;
    return ListenableBuilder(
      listenable: split,
      builder: (context, _) {
        final first = widget.paneFor(split.primary, split.primaryFocus);
        final second = split.second;
        if (!widget.shown || second == null) return first;
        return LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.maxWidth - _dividerWidth;
            final left = (room * split.fraction).floorToDouble();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: left,
                  child: _Pane(focused: !split.secondFocused, onTouch: () => split.focus(second: false), child: first),
                ),
                _Divider(
                  key: SplitPanes.dividerKey,
                  width: _dividerWidth,
                  onDrag: (dx) => split.setFraction(split.fraction + dx / room),
                  onStep: (step) => split.setFraction(split.fraction + step * _keyStep),
                ),
                Expanded(
                  child: _Pane(
                    focused: split.secondFocused,
                    onTouch: () => split.focus(second: true),
                    onClose: split.close,
                    child: widget.paneFor(second, split.secondFocus),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A pane with a border in the accent colour while it has the focus.
class _Pane extends StatelessWidget {
  const _Pane({required this.focused, required this.onTouch, required this.child, this.onClose});

  final bool focused;
  final VoidCallback onTouch;
  final VoidCallback? onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      container: true,
      selected: focused,
      label: onClose == null ? 'Left terminal' : 'Right terminal',
      hint: focused ? null : 'Touch to type here',
      child: Listener(
        // Any touch focuses the pane, without taking the gesture from the
        // terminal (scrolling and selecting still work).
        onPointerDown: (_) => onTouch(),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border.all(color: focused ? colors.accent : colors.outline, width: 2)),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(padding: const EdgeInsets.all(2), child: child),
              ),
              if (onClose != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Material(
                    color: colors.surface.withValues(alpha: 0.85),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Close this pane',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: onClose,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The handle between the panes: drag it sideways, or focus it and use
/// the arrow keys.
class _Divider extends StatelessWidget {
  const _Divider({super.key, required this.width, required this.onDrag, required this.onStep});

  final double width;
  final ValueChanged<double> onDrag;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      label: 'Divider between the terminals',
      hint: 'Drag sideways to change the sizes',
      onIncrease: () => onStep(1),
      onDecrease: () => onStep(-1),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) onStep(-1);
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) onStep(1);
          return event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowRight
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
            child: SizedBox(
              width: width,
              child: Center(
                child: Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(color: colors.muted, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
