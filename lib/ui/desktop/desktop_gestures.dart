import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../sessions/desktop_controller.dart';
import '../../src/rust/api/desktop_types.dart';
import 'desktop_settings.dart';

/// Where the remote screen sits on the phone: screen = origin + remote * k.
/// Pinch zoom changes [k]; panning changes [origin].
class DesktopViewport {
  Offset origin = Offset.zero;

  /// Phone pixels per remote logical pixel.
  double k = 1;

  /// The scale at which the whole remote screen fits.
  double fitK = 1;

  double get zoom => k / fitK;

  Offset toRemote(Offset screen) => (screen - origin) / k;

  Offset toScreen(Offset remote) => origin + remote * k;

  /// Fits [remote] into [view], keeping the zoom (1 = whole screen).
  void layout(Size view, Size remote, {double? zoom}) {
    if (remote.isEmpty || view.isEmpty) return;
    final z = zoom ?? this.zoom;
    fitK = math.min(view.width / remote.width, view.height / remote.height);
    k = fitK * z.clamp(1.0, 6.0);
    _clamp(view, remote);
  }

  /// Zooms by [factor] around the phone point [focal].
  void zoomAround(Offset focal, double factor, Size view, Size remote) {
    final before = toRemote(focal);
    k = (k * factor).clamp(fitK, fitK * 6);
    origin = focal - before * k;
    _clamp(view, remote);
  }

  void panBy(Offset delta, Size view, Size remote) {
    origin += delta;
    _clamp(view, remote);
  }

  /// Pans just enough that [remote] point stays at least [margin] inside
  /// the visible area (height [visibleHeight] when the keyboard is up).
  void follow(Offset remotePoint, Size view, Size remote, {double margin = 48, double? visibleHeight}) {
    final p = toScreen(remotePoint);
    final bottom = visibleHeight ?? view.height;
    var dx = 0.0, dy = 0.0;
    if (p.dx < margin) dx = margin - p.dx;
    if (p.dx > view.width - margin) dx = view.width - margin - p.dx;
    if (p.dy < margin) dy = margin - p.dy;
    if (p.dy > bottom - margin) dy = bottom - margin - p.dy;
    if (dx == 0 && dy == 0) return;
    origin += Offset(dx, dy);
    _clamp(view, remote, visibleHeight: visibleHeight);
  }

  void _clamp(Size view, Size remote, {double? visibleHeight}) {
    final w = remote.width * k, h = remote.height * k;
    final x = w <= view.width ? (view.width - w) / 2 : origin.dx.clamp(view.width - w, 0.0);
    // With the keyboard up the bottom of the screen may slide above it.
    final bottom = visibleHeight ?? view.height;
    final y = h <= bottom ? (visibleHeight != null ? math.min((view.height - h) / 2, bottom - h) : (view.height - h) / 2) : origin.dy.clamp(bottom - h, 0.0);
    origin = Offset(x.toDouble(), y.toDouble());
  }
}

/// Turns touches on the remote screen into pointer, click and scroll
/// input, without the delays of Flutter's gesture arena (which waits to
/// tell taps from double taps): every movement is sent the moment it
/// happens.
///
/// Trackpad mode (default): one finger moves the pointer like a laptop
/// trackpad, tap clicks, two-finger tap right-clicks, two fingers scroll,
/// press and hold then drag selects or moves things, pinch zooms the view.
///
/// Direct mode: tap clicks where the finger is, hold right-clicks, drag
/// drags, two fingers scroll, pinch zooms.
///
/// A mouse (Bluetooth or USB) works as a mouse in both modes.
class DesktopGestures extends StatefulWidget {
  const DesktopGestures({
    super.key,
    required this.controller,
    required this.viewport,
    required this.viewSize,
    required this.onViewChanged,
    required this.onTapEmpty,
    this.visibleHeight,
    required this.child,
  });

  final DesktopController controller;
  final DesktopViewport viewport;
  final Size viewSize;

  /// Zoom or pan changed: redraw.
  final VoidCallback onViewChanged;

  /// A touch that reached the screen, to bring the toolbar back.
  final VoidCallback onTapEmpty;

  /// Height above the phone keyboard while it is open.
  final double? visibleHeight;
  final Widget child;

  @override
  State<DesktopGestures> createState() => _DesktopGesturesState();
}

enum _Two { undecided, scroll, pinch }

class _DesktopGesturesState extends State<DesktopGestures> {
  static const _tapSlop = 10.0;
  static const _tapTime = Duration(milliseconds: 260);
  static const _holdTime = Duration(milliseconds: 420);

  final Map<int, Offset> _touches = {};
  Offset? _start;
  DateTime _startAt = DateTime.now();
  bool _moved = false;
  bool _wasMulti = false;
  bool _dragging = false;
  Timer? _hold;

  // Two fingers.
  _Two _two = _Two.undecided;
  Offset _twoStart = Offset.zero;
  Offset _lastCentroid = Offset.zero;
  double _startSpread = 1;
  double _lastSpread = 1;
  DateTime _twoAt = DateTime.now();
  int _maxTouches = 0;

  // Trackpad feel: small movements stay precise, fast ones go far.
  double _gain(double speed) => 1.0 + math.min(speed / 18.0, 1.6);

  DesktopController get c => widget.controller;
  bool get _trackpad => c.settings.touch == DesktopTouchMode.trackpad;

  void _haptic() {
    if (c.settings.haptics) HapticFeedback.selectionClick();
  }

  Offset get _centroid {
    var sum = Offset.zero;
    for (final p in _touches.values) {
      sum += p;
    }
    return sum / _touches.length.toDouble();
  }

  double get _spread {
    final pts = _touches.values.toList();
    if (pts.length < 2) return 1;
    return (pts[0] - pts[1]).distance.clamp(1.0, double.infinity);
  }

  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse) return _mouseDown(e);
    widget.onTapEmpty();
    _touches[e.pointer] = e.localPosition;
    _maxTouches = math.max(_maxTouches, _touches.length);
    if (_touches.length == 1) {
      _start = e.localPosition;
      _startAt = DateTime.now();
      _moved = false;
      _wasMulti = false;
      _hold?.cancel();
      _hold = Timer(_holdTime, _onHold);
    } else if (_touches.length == 2) {
      _hold?.cancel();
      _endDrag();
      _wasMulti = true;
      _two = _Two.undecided;
      _twoStart = _centroid;
      _lastCentroid = _centroid;
      _startSpread = _spread;
      _lastSpread = _spread;
      _twoAt = DateTime.now();
    }
  }

  void _onHold() {
    if (_moved || _touches.length != 1 || _start == null) return;
    if (_trackpad) {
      // Hold, then drag: the button stays down (select text, move windows).
      _dragging = true;
      c.steering = true;
      c.press(DesktopButton.left);
    } else {
      c.moveTo(widget.viewport.toRemote(_start!));
      c.click(DesktopButton.right);
    }
    if (c.settings.haptics) HapticFeedback.mediumImpact();
  }

  void _move(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.mouse) return _mouseMove(e);
    final prev = _touches[e.pointer];
    if (prev == null) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 1 && !_wasMulti) {
      if (!_moved && (e.localPosition - _start!).distance > _tapSlop) {
        _moved = true;
        if (!_dragging) _hold?.cancel();
        if (!_trackpad && !_dragging) {
          // Direct drag: press where the finger started.
          c.moveTo(widget.viewport.toRemote(_start!));
          _dragging = true;
          c.press(DesktopButton.left);
        }
      }
      if (!_moved) return;
      if (_trackpad) {
        c.steering = true;
        final delta = e.localPosition - prev;
        final gain = _gain(delta.distance);
        // Finger movement in phone pixels, turned into remote pixels at the
        // current zoom: the pointer moves as far as the finger looks to.
        c.moveBy(delta * gain / widget.viewport.k);
        if (widget.viewport.zoom > 1.01 || widget.visibleHeight != null) {
          widget.viewport.follow(c.cursor, widget.viewSize, c.remoteSize, visibleHeight: widget.visibleHeight);
          widget.onViewChanged();
        }
      } else {
        c.moveTo(widget.viewport.toRemote(e.localPosition));
      }
      return;
    }
    if (_touches.length == 2) _twoMove();
  }

  void _twoMove() {
    final centroid = _centroid;
    final spread = _spread;
    if (_two == _Two.undecided) {
      final ratio = spread / _startSpread;
      if ((ratio - 1).abs() > 0.08) {
        _two = _Two.pinch;
      } else if ((centroid - _twoStart).distance > 12) {
        _two = _Two.scroll;
      } else {
        return;
      }
    }
    if (_two == _Two.pinch) {
      widget.viewport.zoomAround(centroid, spread / _lastSpread, widget.viewSize, c.remoteSize);
      widget.viewport.panBy(centroid - _lastCentroid, widget.viewSize, c.remoteSize);
      widget.onViewChanged();
    } else {
      // Natural scrolling: content follows the fingers.
      final d = (centroid - _lastCentroid) / widget.viewport.k;
      c.scroll(-d.dx * 1.6, -d.dy * 1.6);
    }
    _lastCentroid = centroid;
    _lastSpread = spread;
  }

  void _up(PointerEvent e) {
    if (e.kind == PointerDeviceKind.mouse) return _mouseUp(e);
    if (!_touches.containsKey(e.pointer)) return;
    final wasCount = _touches.length;
    _touches.remove(e.pointer);
    final quick = DateTime.now().difference(_wasMulti ? _twoAt : _startAt) < _tapTime;

    if (wasCount == 2 && _touches.length == 1) {
      // Second finger lifted: finish the two-finger gesture.
      if (_two == _Two.scroll) c.scrollStop();
      if (_two == _Two.undecided && quick && _maxTouches == 2) {
        if (!_trackpad) c.moveTo(widget.viewport.toRemote(_twoStart));
        c.click(DesktopButton.right);
        _haptic();
      }
      if (_maxTouches == 3 && _two == _Two.undecided && quick) {
        c.click(DesktopButton.middle);
        _haptic();
      }
      _two = _Two.undecided;
      return;
    }
    if (_touches.isNotEmpty) return;
    _hold?.cancel();
    if (_dragging) {
      _endDrag();
    } else if (!_wasMulti && !_moved && quick) {
      if (!_trackpad) c.moveTo(widget.viewport.toRemote(_start!));
      c.click(DesktopButton.left);
      _haptic();
    }
    c.steering = false;
    _maxTouches = 0;
    _wasMulti = false;
  }

  void _endDrag() {
    if (_dragging) {
      c.release(DesktopButton.left);
      _dragging = false;
    }
  }

  // A real mouse: absolute position, real buttons, real wheel.

  int _mouseButtons = 0;

  void _mouseDown(PointerDownEvent e) {
    c.moveTo(widget.viewport.toRemote(e.localPosition));
    _syncButtons(e.buttons);
  }

  void _mouseMove(PointerEvent e) {
    c.moveTo(widget.viewport.toRemote(e.localPosition));
    _syncButtons(e.buttons);
  }

  void _mouseUp(PointerEvent e) => _syncButtons(e.buttons);

  void _syncButtons(int buttons) {
    const map = {kPrimaryButton: DesktopButton.left, kSecondaryButton: DesktopButton.right, kMiddleMouseButton: DesktopButton.middle};
    for (final entry in map.entries) {
      final was = _mouseButtons & entry.key != 0, now = buttons & entry.key != 0;
      if (now && !was) c.press(entry.value);
      if (!now && was) c.release(entry.value);
    }
    _mouseButtons = buttons;
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final d = e.scrollDelta / widget.viewport.k;
      c.scroll(d.dx, d.dy);
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _endDrag();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      onPointerHover: (e) {
        if (e.kind == PointerDeviceKind.mouse) _mouseMove(e);
      },
      onPointerSignal: _signal,
      child: widget.child,
    );
  }
}
