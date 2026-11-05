import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Moves between the main screens with a finger on the bottom bar: slide
/// along it, or press, hold and slide. The screens follow the finger and
/// settle on the nearest one on release. Holding Settings without moving
/// opens the theme switcher instead. A plain tap still opens a tab.
///
/// The bar's items all have the same width, so the screen under the finger
/// follows from where it is.
class TabScrub extends StatefulWidget {
  const TabScrub({
    super.key,
    required this.count,
    required this.pages,
    required this.settingsSlot,
    required this.onHoldSettings,
    required this.child,
  });

  final int count;
  final PageController pages;
  final int settingsSlot;
  final VoidCallback onHoldSettings;
  final Widget child;

  @override
  State<TabScrub> createState() => _TabScrubState();
}

class _TabScrubState extends State<TabScrub> {
  int? _heldSlot;
  bool _moved = false;

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  /// The slot under [x], counted from the start of the bar.
  int _slotAt(double x, double width) {
    final slot = (x / width * widget.count).floor().clamp(0, widget.count - 1);
    return _rtl ? widget.count - 1 - slot : slot;
  }

  /// The screen position under [x]: 0 at the middle of the first item.
  double _pageAt(double x, double width) {
    final page = (x / width * widget.count - 0.5).clamp(0.0, widget.count - 1.0);
    return _rtl ? widget.count - 1 - page : page;
  }

  void _follow(double x, double width) {
    final pages = widget.pages;
    if (!pages.hasClients || !pages.position.haveDimensions) return;
    pages.jumpTo(_pageAt(x, width) * pages.position.viewportDimension);
  }

  void _settle() {
    final pages = widget.pages;
    if (!pages.hasClients || !pages.position.haveDimensions) return;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 240);
    final target = (pages.page ?? 0).round();
    if (duration == Duration.zero) {
      pages.jumpToPage(target);
    } else {
      pages.animateToPage(target, duration: duration, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (d) => _follow(d.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _settle(),
            onHorizontalDragCancel: _settle,
            onLongPressStart: (d) {
              _heldSlot = _slotAt(d.localPosition.dx, width);
              _moved = false;
              HapticFeedback.mediumImpact();
            },
            onLongPressMoveUpdate: (d) {
              if (!_moved && _slotAt(d.localPosition.dx, width) == _heldSlot) return;
              _moved = true;
              _follow(d.localPosition.dx, width);
            },
            onLongPressEnd: (_) {
              if (!_moved && _heldSlot == widget.settingsSlot) {
                widget.onHoldSettings();
              } else {
                _settle();
              }
              _heldSlot = null;
            },
            child: widget.child,
          );
        },
      );
}

/// The mark behind the open tab of a bar with [count] equal items. It
/// follows the screens as they move: the edge in front goes first and the
/// one behind catches up, so it stretches across and flows into the next
/// tab, and it thins a little while stretched.
class FlowingTabIndicator extends StatelessWidget {
  const FlowingTabIndicator({
    super.key,
    required this.count,
    required this.pages,
    required this.index,
    required this.color,
    required this.size,
  });

  final int count;
  final PageController pages;

  /// The open tab, used before the screens are laid out.
  final int index;
  final Color color;

  /// The mark at rest.
  final Size size;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final slot = box.maxWidth / count;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          return ListenableBuilder(
            listenable: pages,
            builder: (context, _) {
              final page = pages.hasClients && pages.position.haveDimensions ? pages.page ?? index.toDouble() : index.toDouble();
              final (left, right) = edges(page, count: count, slot: slot, width: size.width);
              final stretch = ((right - left - size.width) / slot).clamp(0.0, 1.0);
              final height = size.height * (1 - 0.18 * stretch);
              final x = rtl ? box.maxWidth - right : left;
              return Stack(
                children: [
                  Positioned(
                    left: x,
                    width: right - left,
                    top: (box.maxHeight - height) / 2,
                    height: height,
                    child: IgnorePointer(
                      child: DecoratedBox(decoration: ShapeDecoration(color: color, shape: const StadiumBorder())),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

  /// The left and right edges of a mark [width] wide at screen position
  /// [page] (fractional while moving), counted from the start of the bar.
  /// The right edge eases out and the left one eases in, so whichever way
  /// it moves, the edge in front leads and the mark stretches between.
  static (double, double) edges(double page, {required int count, required double slot, required double width}) {
    final p = page.clamp(0.0, count - 1.0);
    final from = p.floor();
    final to = (from + 1).clamp(0, count - 1);
    final f = p - from;
    double centre(int i) => (i + 0.5) * slot;
    final lead = Curves.easeOutCubic.transform(f);
    final trail = Curves.easeInCubic.transform(f);
    final left = lerpDouble(centre(from), centre(to), trail)! - width / 2;
    final right = lerpDouble(centre(from), centre(to), lead)! + width / 2;
    return (left, right);
  }
}
