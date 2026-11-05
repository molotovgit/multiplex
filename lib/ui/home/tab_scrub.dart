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
