/// Decides when the app looks for a new version by itself: at start-up,
/// at most once a day, and only when the user has not turned it off.
abstract final class UpdateSchedule {
  static const interval = Duration(days: 1);

  /// [lastCheckMs] is when GitHub last answered (0 = never). A time in the
  /// future (the phone's clock was moved back) counts as due, so a wrong
  /// clock cannot stop checks for good.
  static bool isDue({required bool enabled, required int lastCheckMs, required DateTime now}) {
    if (!enabled) return false;
    if (lastCheckMs <= 0) return true;
    final elapsed = now.millisecondsSinceEpoch - lastCheckMs;
    return elapsed < 0 || elapsed >= interval.inMilliseconds;
  }
}
