/// Something went wrong while checking for, downloading or checking an
/// update. [message] is shown to the user as it is.
class UpdateException implements Exception {
  const UpdateException(this.message, {this.quiet = false});

  final String message;

  /// No internet or GitHub's hourly limit: not worth a message when the
  /// app checked by itself.
  final bool quiet;

  static const offline = UpdateException('Could not reach GitHub. Check your internet connection and try again.', quiet: true);
  static const rateLimited = UpdateException('GitHub asks to wait before checking again (too many checks in an hour). Try again later.', quiet: true);
  static const cancelled = UpdateException('Download cancelled.', quiet: true);

  @override
  String toString() => message;
}

/// Lets the user stop a download part way.
class UpdateCancel {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Runs [listener] when cancelled (at once if it already was).
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}
