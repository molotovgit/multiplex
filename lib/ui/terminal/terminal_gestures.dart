/// What a step of a drag or pinch on the terminal should do.
sealed class GestureStep {
  const GestureStep();
}

/// Scroll by this many pixels (positive = finger moved down).
class ScrollStep extends GestureStep {
  const ScrollStep(this.pixels);

  final double pixels;
}

/// Show the text at this size for now (not saved yet).
class FontStep extends GestureStep {
  const FontStep(this.size);

  final double size;
}

/// Nothing to do yet.
class NoStep extends GestureStep {
  const NoStep();
}

/// Tells a pinch from a two-finger scroll and follows either.
///
/// One finger always scrolls. With two fingers the first clear movement
/// decides: the fingers moving apart or together is a pinch (font size),
/// both moving up or down together is a scroll. Once decided the gesture
/// stays what it is, so a pinch never scrolls by accident.
///
/// Flutter starts a new gesture whenever a finger is added or lifted, so
/// every [start] says how many fingers there are.
class TerminalGestureTracker {
  TerminalGestureTracker({required this.minSize, required this.maxSize});

  final double minSize;
  final double maxSize;

  /// The fingers spread or closed by this much (8 %): a pinch.
  static const pinchSlop = 0.08;

  /// The fingers moved this far up or down together: a scroll.
  static const scrollSlop = 12.0;

  _Mode _mode = _Mode.undecided;
  double _startSize = 0;
  double _size = 0;
  double _travel = 0;

  bool get isPinching => _mode == _Mode.pinch;

  void start({required int pointers, required double fontSize}) {
    _mode = pointers > 1 ? _Mode.undecided : _Mode.scroll;
    _startSize = fontSize;
    _size = fontSize;
    _travel = 0;
  }

  /// `scale` is the spread of the fingers since [start] (1 = unchanged),
  /// `dy` the vertical movement of their middle since the last update.
  GestureStep update({required double scale, required double dy}) {
    if (_mode == _Mode.undecided) {
      _travel += dy;
      if ((scale - 1).abs() >= pinchSlop) {
        _mode = _Mode.pinch;
      } else if (_travel.abs() >= scrollSlop) {
        _mode = _Mode.scroll;
        return ScrollStep(_travel);
      } else {
        return const NoStep();
      }
    }
    switch (_mode) {
      case _Mode.pinch:
        final size = (_startSize * scale).roundToDouble().clamp(minSize, maxSize);
        if (size == _size) return const NoStep();
        _size = size;
        return FontStep(size);
      case _Mode.scroll:
        return dy == 0 ? const NoStep() : ScrollStep(dy);
      case _Mode.undecided:
        return const NoStep();
    }
  }

  /// The size to save when a pinch ends, or null when the size did not
  /// change (or the gesture was not a pinch).
  double? end() {
    final pinched = _mode == _Mode.pinch && _size != _startSize;
    _mode = _Mode.undecided;
    return pinched ? _size : null;
  }
}

enum _Mode { undecided, pinch, scroll }
