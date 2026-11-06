import 'command_capture.dart';

/// A command that ran and ended.
class FinishedCommand {
  const FinishedCommand(this.command, this.took, {this.exitCode});

  final String command;
  final Duration took;

  /// Known only from shell integration (OSC 133).
  final int? exitCode;
}

/// Times the commands of one terminal, to say when a long one is done.
///
/// A command starts when the command capture reads it at Enter. It ends
/// when its prompt comes back: the cursor sits right after the same
/// prompt text again, outside a full-screen program, after it had left
/// it. A shell set up for shell integration (OSC 133) says both itself;
/// once it does, only its marks count.
class CommandTimer {
  CommandTimer({required this.onFinished, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final void Function(FinishedCommand done) onFinished;
  final DateTime Function() _clock;

  /// The shell sends OSC 133 marks; the screen is not read any more.
  bool _marks = false;
  _Running? _running;

  /// When a mark started a command whose text is not read yet.
  DateTime? _markStart;

  /// The command capture read a command at Enter.
  void ran(String command, String prompt, int promptCol) {
    if (_marks) {
      final start = _markStart;
      if (start != null) _running = _Running(command, prompt, promptCol, start)..left = true;
      return;
    }
    _running = _Running(command, prompt, promptCol, _clock());
  }

  /// OSC 133 "C".
  void markStarted() {
    _marks = true;
    _markStart = _clock();
    _running = null;
  }

  /// OSC 133 "D".
  void markFinished(int? exitCode) {
    _marks = true;
    final start = _markStart;
    final command = _running?.command ?? '';
    _markStart = null;
    _running = null;
    if (start != null) onFinished(FinishedCommand(command, _clock().difference(start), exitCode: exitCode));
  }

  /// Call with every new frame.
  void onFrame(ScreenText screen) {
    final running = _running;
    if (_marks || running == null || screen.alternateScreen || screen.scrolledBack) return;
    final atPrompt = _atPrompt(screen, running);
    if (!atPrompt) {
      running.left = true;
    } else if (running.left) {
      _running = null;
      onFinished(FinishedCommand(running.command, _clock().difference(running.startedAt)));
    }
  }

  /// The user gave up on the terminal (closed, connection lost).
  void reset() {
    _running = null;
    _markStart = null;
  }

  bool _atPrompt(ScreenText s, _Running r) {
    if (s.cursorCol != r.promptCol || r.prompt.trim().isEmpty) return false;
    return s.between(s.cursorRow, 0, s.cursorRow, r.promptCol - 1) == r.prompt;
  }
}

class _Running {
  _Running(this.command, this.prompt, this.promptCol, this.startedAt);

  final String command;
  final String prompt;
  final int promptCol;
  final DateTime startedAt;

  /// The cursor moved away from the prompt since the command started.
  bool left = false;
}
