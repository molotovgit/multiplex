import 'package:flutter/material.dart';

/// Pinch to zoom and drag around; a double tap zooms in on that spot or
/// back out. Tells [onZoomed] when it leaves or returns to the normal
/// size, so a page swiper can stop swiping while zoomed in.
class ZoomView extends StatefulWidget {
  const ZoomView({super.key, required this.child, this.onZoomed, this.maxScale = 8});

  final Widget child;
  final ValueChanged<bool>? onZoomed;
  final double maxScale;

  /// How far a double tap zooms in.
  static const doubleTapScale = 2.5;

  @override
  State<ZoomView> createState() => ZoomViewState();
}

class ZoomViewState extends State<ZoomView> {
  final _transform = TransformationController();
  Offset _lastTap = Offset.zero;
  bool _zoomed = false;

  double get scale => _transform.value.getMaxScaleOnAxis();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _report() {
    final zoomed = scale > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomed?.call(zoomed);
  }

  /// Zooms in around the tapped point, or back to the whole picture. The
  /// jump is instant: no animation to switch off for reduced motion.
  void _doubleTap() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      const s = ZoomView.doubleTapScale;
      final p = _lastTap;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _report();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _lastTap = details.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: widget.maxScale,
        onInteractionEnd: (_) => _report(),
        onInteractionUpdate: (_) => _report(),
        child: widget.child,
      ),
    );
  }
}
