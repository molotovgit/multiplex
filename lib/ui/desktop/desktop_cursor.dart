import 'package:flutter/material.dart';

import '../../sessions/desktop_controller.dart';
import 'desktop_gestures.dart';

/// Draws the pointer on the phone, at the position the phone already
/// knows. The pointer follows the finger at once instead of waiting for
/// the remote to report it back, so steering feels immediate even on a
/// slow network. The remote's own cursor picture is used when it sent
/// one; otherwise a plain arrow.
class DesktopCursorPainter extends CustomPainter {
  DesktopCursorPainter(this.controller, this.viewport) : super(repaint: controller);

  final DesktopController controller;
  final DesktopViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final at = viewport.toScreen(controller.cursor);
    final image = controller.cursorImage;
    if (image != null) {
      // The picture is in remote pixels; on screen it is as large as the
      // remote shows it, at the current zoom.
      final s = viewport.k / controller.remoteScale;
      final hot = controller.cursorHot * s;
      final dst = Rect.fromLTWH(at.dx - hot.dx, at.dy - hot.dy, image.width * s, image.height * s);
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    // A plain arrow, about 20 px tall on the phone.
    final arrow = Path()
      ..moveTo(at.dx, at.dy)
      ..lineTo(at.dx, at.dy + 20)
      ..lineTo(at.dx + 5, at.dy + 15.5)
      ..lineTo(at.dx + 8.5, at.dy + 22.5)
      ..lineTo(at.dx + 11.5, at.dy + 21)
      ..lineTo(at.dx + 8, at.dy + 14)
      ..lineTo(at.dx + 14.5, at.dy + 14)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(DesktopCursorPainter old) => true;
}
