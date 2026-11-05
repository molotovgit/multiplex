import 'dart:async';

/// Repeats a key while it is held: the first repeat comes after [delay],
/// then one every [interval].
class KeyRepeater {
  static const delay = Duration(milliseconds: 400);
  static const interval = Duration(milliseconds: 50);

  Timer? _wait;
  Timer? _tick;
  int _fired = 0;

  /// How many times the key repeated since [start].
  int get fired => _fired;

  bool get running => _wait != null || _tick != null;

  void start(void Function() fire) {
    stop();
    _fired = 0;
    _wait = Timer(delay, () {
      _wait = null;
      _fire(fire);
      _tick = Timer.periodic(interval, (_) => _fire(fire));
    });
  }

  void stop() {
    _wait?.cancel();
    _tick?.cancel();
    _wait = null;
    _tick = null;
  }

  void _fire(void Function() fire) {
    _fired++;
    fire();
  }
}
