import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cast_file.dart';

/// Where a player shows the recording.
abstract interface class CastScreen {
  void feed(String text);
  void resize(int cols, int rows);

  /// Empties the screen, to play from the start again.
  void reset();
}

/// Plays a [CastFile] onto a [CastScreen] in real time, faster if asked.
/// Long quiet stretches are cut to [maxPause], as asciinema does, so a
/// recording of a slow build does not make you wait.
class CastPlayer extends ChangeNotifier {
  CastPlayer(this.cast, this.screen);

  static const speeds = [1.0, 2.0, 4.0];
  static const maxPause = 2.0;

  final CastFile cast;
  final CastScreen screen;

  int _next = 0;
  double _speed = 1;
  bool _playing = false;
  Timer? _timer;

  /// Where the playback is, in seconds of the recording.
  double _position = 0;

  bool get playing => _playing;
  bool get finished => _next >= cast.events.length;
  double get speed => _speed;
  double get position => _position;

  void play() {
    if (_playing) return;
    if (finished) _restart();
    _playing = true;
    _schedule();
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _timer?.cancel();
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  /// 1x, 2x or 4x.
  void setSpeed(double speed) {
    _speed = speed;
    if (_playing) {
      _timer?.cancel();
      _schedule();
    }
    notifyListeners();
  }

  void _restart() {
    _next = 0;
    _position = 0;
    screen.reset();
  }

  void _schedule() {
    if (!_playing) return;
    if (finished) {
      _playing = false;
      notifyListeners();
      return;
    }
    final wait = (cast.events[_next].at - _position).clamp(0.0, maxPause) / _speed;
    _timer = Timer(Duration(microseconds: (wait * 1e6).round()), _step);
  }

  /// Shows the next event, and every event due at the same moment.
  void _step() {
    final at = cast.events[_next].at;
    while (!finished && cast.events[_next].at <= at) {
      _apply(cast.events[_next]);
      _next++;
    }
    _position = at;
    notifyListeners();
    _schedule();
  }

  void _apply(CastEvent event) {
    switch (event.kind) {
      case 'o':
        screen.feed(event.data);
      case 'r':
        final size = event.data.split('x');
        final cols = int.tryParse(size.first), rows = size.length > 1 ? int.tryParse(size[1]) : null;
        if (cols != null && rows != null) screen.resize(cols, rows);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
