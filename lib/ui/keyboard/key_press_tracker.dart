import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../src/rust/api/terminal_types.dart';
import 'key_repeater.dart';
import 'key_spec.dart';

/// Where the finger is in one press of a key.
enum PressPhase {
  idle,

  /// Down, nothing else yet. Release sends the key.
  pressed,

  /// Long press: the alternates popup is open; release sends the choice.
  choosing,

  /// Swiped up: release sends the first alternate.
  swiped,

  /// Dragging on the space bar moves the cursor.
  trackpad,

  /// Held: the key is repeating.
  repeating,

  /// The press turned into a scroll of the row; nothing is sent.
  cancelled,
}

/// Where the alternates popup sits over a key, in the key's own
/// coordinates, so a finger position can be turned into a choice.
class ChoiceGeometry {
  const ChoiceGeometry({required this.left, required this.cell, required this.count});

  /// The popup's left edge relative to the key's left edge.
  final double left;
  final double cell;
  final int count;

  double get width => cell * count;

  int indexAt(double x) => ((x - left) / cell).floor().clamp(0, count - 1);
}

/// How a key reacts to movement; set by the widget from the settings.
class PressOptions {
  const PressOptions({this.swipe = true, this.swipeDistance = 24, this.inScrollingRow = false});

  /// Swiping up types the first alternate.
  final bool swipe;
  final double swipeDistance;

  /// The key sits in a row that scrolls sideways: moving cancels it.
  final bool inScrollingRow;
}

/// Follows one finger on one key and decides what to send: a tap, an
/// alternate (long press or swipe up), repeats while held, or cursor
/// steps while dragging the space bar. Has no widgets, so it is tested on
/// its own.
class KeyPressTracker extends ChangeNotifier {
  KeyPressTracker({required this.onSend, required this.onCursor});

  static const longPress = Duration(milliseconds: 350);

  /// Movement smaller than this is still a tap.
  static const slop = 10.0;

  /// Space bar trackpad: one arrow per this much movement. Up and down
  /// need more, so a sideways drag does not jump through history.
  static const stepX = 14.0;
  static const stepY = 28.0;

  final ValueChanged<KeySpec> onSend;
  final ValueChanged<TerminalKey> onCursor;

  final _repeater = KeyRepeater();
  Timer? _hold;
  KeySpec? _spec;
  PressOptions _options = const PressOptions();
  ChoiceGeometry? _geometry;
  PressPhase _phase = PressPhase.idle;
  Offset _start = Offset.zero;
  Offset _anchor = Offset.zero;
  int _choice = 0;

  PressPhase get phase => _phase;

  /// The alternate the finger is over while [phase] is [PressPhase.choosing].
  int get choice => _choice;
  ChoiceGeometry? get geometry => _geometry;

  bool get isDown => _phase != PressPhase.idle && _phase != PressPhase.cancelled;

  /// What the preview bubble shows: the alternate after a swipe up.
  KeySpec? get previewKey => switch (_phase) {
        PressPhase.pressed || PressPhase.repeating => _spec,
        PressPhase.swiped => _spec?.alternates.first,
        _ => null,
      };

  void down(Offset position, KeySpec spec, {PressOptions options = const PressOptions(), ChoiceGeometry? geometry}) {
    _stopTimers();
    _spec = spec;
    _options = options;
    _geometry = geometry;
    _start = position;
    _anchor = position;
    _choice = 0;
    _phase = PressPhase.pressed;
    if (spec.alternates.isNotEmpty) {
      _hold = Timer(longPress, _openChoices);
    } else if (spec.repeats) {
      _repeater.start(_repeat);
    }
    notifyListeners();
  }

  void move(Offset position) {
    final spec = _spec;
    if (spec == null) return;
    final d = position - _start;
    switch (_phase) {
      case PressPhase.choosing:
        final next = _geometry?.indexAt(position.dx) ?? 0;
        if (next != _choice) {
          _choice = next;
          notifyListeners();
        }
      case PressPhase.trackpad:
        _track(position);
      case PressPhase.pressed || PressPhase.repeating:
        if (spec.trackpad && d.distance > slop) {
          _stopTimers();
          _phase = PressPhase.trackpad;
          _track(position);
          notifyListeners();
        } else if (_options.swipe && spec.alternates.isNotEmpty && -d.dy > _options.swipeDistance && d.dy.abs() > d.dx.abs()) {
          _stopTimers();
          _phase = PressPhase.swiped;
          notifyListeners();
        } else if (_options.inScrollingRow && d.dx.abs() > slop) {
          _stopTimers();
          _phase = PressPhase.cancelled;
          notifyListeners();
        }
      case PressPhase.idle || PressPhase.swiped || PressPhase.cancelled:
        break;
    }
  }

  void up() {
    final spec = _spec;
    if (spec != null) {
      switch (_phase) {
        case PressPhase.pressed:
          onSend(spec);
        case PressPhase.choosing:
          onSend(spec.alternates[_choice]);
        case PressPhase.swiped:
          onSend(spec.alternates.first);
        case PressPhase.repeating || PressPhase.trackpad || PressPhase.cancelled || PressPhase.idle:
          break;
      }
    }
    _reset();
  }

  void cancel() => _reset();

  void _openChoices() {
    _hold = null;
    if (_phase != PressPhase.pressed) return;
    _phase = PressPhase.choosing;
    notifyListeners();
  }

  void _repeat() {
    final spec = _spec;
    if (spec == null) return;
    if (_phase == PressPhase.pressed) {
      _phase = PressPhase.repeating;
      notifyListeners();
    }
    onSend(spec);
  }

  /// Sends one arrow for each full step the finger moved since the last.
  void _track(Offset position) {
    while (position.dx - _anchor.dx >= stepX) {
      _anchor = _anchor.translate(stepX, 0);
      onCursor(TerminalKey.right);
    }
    while (_anchor.dx - position.dx >= stepX) {
      _anchor = _anchor.translate(-stepX, 0);
      onCursor(TerminalKey.left);
    }
    while (position.dy - _anchor.dy >= stepY) {
      _anchor = _anchor.translate(0, stepY);
      onCursor(TerminalKey.down);
    }
    while (_anchor.dy - position.dy >= stepY) {
      _anchor = _anchor.translate(0, -stepY);
      onCursor(TerminalKey.up);
    }
  }

  void _stopTimers() {
    _hold?.cancel();
    _hold = null;
    _repeater.stop();
  }

  void _reset() {
    _stopTimers();
    final changed = _phase != PressPhase.idle;
    _phase = PressPhase.idle;
    _spec = null;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }
}
