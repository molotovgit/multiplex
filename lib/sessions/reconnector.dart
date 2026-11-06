import 'dart:async';

/// What one reconnect attempt came to.
enum ReconnectResult {
  /// Logged in again; the terminals are back.
  connected,

  /// The server could not be reached (yet). Try again later.
  retry,

  /// Logging in again would need the user (a password that is not saved,
  /// a new host key). Never ask in a loop: stop here.
  giveUp,
}

/// Where a reconnect stands, for the "Reconnecting…" banner.
class ReconnectStatus {
  const ReconnectStatus({required this.attempt, this.nextTryAt, this.trying = false});

  /// Attempts made so far.
  final int attempt;

  /// When the next attempt starts, while waiting for it.
  final DateTime? nextTryAt;

  /// An attempt is running right now.
  final bool trying;
}

/// Starts a timer; tests pass a fake one.
typedef ReconnectTimerFactory = Timer Function(Duration delay, void Function() callback);

/// Tries to log in again after a connection dropped: soon at first, then
/// less often (1, 2, 4, 8, 15, then every 30 seconds), and gives up after
/// about five minutes. [retryNow] skips the wait, for example when the
/// phone reports that the network is back.
class Reconnector {
  Reconnector({
    required this.tryOnce,
    required this.onStatus,
    required this.onDone,
    ReconnectTimerFactory? timer,
    DateTime Function()? clock,
  })  : _timer = timer ?? Timer.new,
        _clock = clock ?? DateTime.now;

  /// The waits between attempts, in seconds; the last one repeats.
  static const delays = [1, 2, 4, 8, 15, 30];

  /// No new attempt starts after this long.
  static const giveUpAfter = Duration(minutes: 5);

  final Future<ReconnectResult> Function() tryOnce;
  final void Function(ReconnectStatus status) onStatus;

  /// Called once at the end: true when the connection is back.
  final void Function(bool connected) onDone;
  final ReconnectTimerFactory _timer;
  final DateTime Function() _clock;

  late DateTime _startedAt;
  int _attempt = 0;
  Timer? _wait;
  bool _trying = false;
  bool _finished = false;

  bool get finished => _finished;

  /// The wait before attempt number [attempt] (0-based).
  static Duration delayBefore(int attempt) => Duration(seconds: delays[attempt.clamp(0, delays.length - 1)]);

  void start() {
    _startedAt = _clock();
    _schedule();
  }

  /// Tries at once instead of waiting (no effect while an attempt runs).
  void retryNow() {
    if (_finished || _trying) return;
    _wait?.cancel();
    _run();
  }

  /// Stops for good, without calling [onDone].
  void cancel() {
    _finished = true;
    _wait?.cancel();
  }

  void _schedule() {
    if (_finished) return;
    if (_clock().difference(_startedAt) >= giveUpAfter) {
      _finish(false);
      return;
    }
    final delay = delayBefore(_attempt);
    onStatus(ReconnectStatus(attempt: _attempt, nextTryAt: _clock().add(delay)));
    _wait = _timer(delay, _run);
  }

  Future<void> _run() async {
    if (_finished || _trying) return;
    _trying = true;
    _attempt++;
    onStatus(ReconnectStatus(attempt: _attempt, trying: true));
    ReconnectResult result;
    try {
      result = await tryOnce();
    } catch (_) {
      result = ReconnectResult.retry;
    }
    _trying = false;
    if (_finished) return;
    switch (result) {
      case ReconnectResult.connected:
        _finish(true);
      case ReconnectResult.giveUp:
        _finish(false);
      case ReconnectResult.retry:
        _schedule();
    }
  }

  void _finish(bool connected) {
    if (_finished) return;
    _finished = true;
    _wait?.cancel();
    onDone(connected);
  }
}
