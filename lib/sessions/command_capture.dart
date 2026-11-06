import '../src/rust/api/terminal.dart';
import '../src/rust/api/terminal_types.dart';

/// What the command capture reads from a terminal screen.
abstract interface class ScreenText {
  int get rows;
  int get cols;
  int get cursorRow;
  int get cursorCol;

  /// A full-screen program (vim, htop, less) is running.
  bool get alternateScreen;

  /// The view is scrolled back into history, so rows are not the live ones.
  bool get scrolledBack;

  /// Text between two cells, both included. Rows that wrapped into the
  /// next one are joined without a line break; other rows end with "\n".
  String between(int startRow, int startCol, int endRow, int endCol);

  /// True when the row's text reaches the last column, so the line may
  /// go on in the next row.
  bool rowIsFull(int row);
}

/// [ScreenText] over a live terminal frame and its shell.
class FrameScreenText implements ScreenText {
  const FrameScreenText(this.frame, this.shell);

  final TerminalFrame frame;
  final RemoteShell shell;

  @override
  int get rows => frame.rows;

  @override
  int get cols => frame.cols;

  @override
  int get cursorRow => frame.cursor.row;

  @override
  int get cursorCol => frame.cursor.col;

  @override
  bool get alternateScreen => frame.alternateScreen;

  @override
  bool get scrolledBack => frame.scrollOffset != 0;

  @override
  String between(int startRow, int startCol, int endRow, int endCol) =>
      shell.textBetween(startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol);

  @override
  bool rowIsFull(int row) => RowCells.lastUsedCell(frame.lines[row]) >= frame.cols;
}

/// Spots a password prompt at the cursor ("Password:", "[sudo] password
/// for alice:", "Enter passphrase for key:"). Typing there never echoes,
/// which is how the command capture keeps it out of the history; this
/// sees the prompt itself, before any key, so a recording can stop.
abstract final class PasswordPrompt {
  static final _prompt = RegExp(r'(password|passphrase|passcode|\bpin\b)[^:\n]{0,40}:\s*$', caseSensitive: false);

  static bool at(ScreenText screen) {
    if (screen.alternateScreen || screen.scrolledBack || screen.cursorCol == 0) return false;
    final row = screen.cursorRow;
    final from = (screen.cursorCol - 80).clamp(0, screen.cursorCol);
    return _prompt.hasMatch(screen.between(row, from, row, screen.cursorCol - 1));
  }
}

/// Measures rows of a frame.
abstract final class RowCells {
  /// The column just after the last non-blank character of a row.
  static int lastUsedCell(TerminalLine line) {
    var end = 0;
    for (final run in line.runs) {
      final trimmed = run.text.trimRight();
      if (trimmed.isEmpty) continue;
      // A run with trailing blanks ends where its last character does
      // (counting one cell each; wide characters never end in blanks).
      final cells = trimmed.length == run.text.length ? run.width : trimmed.runes.length;
      if (run.col + cells > end) end = run.col + cells;
    }
    return end;
  }
}

/// The line being typed: where its prompt ends and what the row showed
/// before the first key.
class _Line {
  _Line({required this.row, required this.col, required this.prompt, required this.before});

  final int row;
  final int col;

  /// The row's text in front of the cursor at the first key.
  final String prompt;

  /// The whole row at the first key, to tell whether typing echoed.
  final String before;
  bool echoed = false;
}

/// A command whose Enter was sent; it is read once more when the shell
/// answers, so a late echo or a tab completion is included.
class _Pending {
  _Pending(this.line, this.text, this.cursorRow, this.cursorCol, {required this.echoed});

  final _Line line;

  /// The line had echoed by the time Enter was pressed. If not, only a
  /// later read counts: a slow link may echo after Enter, a password
  /// prompt never does.
  final bool echoed;

  /// What the line said when Enter was pressed.
  final String text;
  final int cursorRow;
  final int cursorCol;
  int frames = 0;
}

/// Finds the commands the user runs in a terminal, by reading the screen
/// instead of the keystrokes: tab completion, history recall and edits
/// all end up right.
///
/// Before the first key of a line the cursor position marks the end of
/// the prompt. At Enter the line is read from there to its end, across
/// wrapped rows. Nothing is kept from full-screen programs, from lines
/// that never echoed (password prompts), from empty lines, or from lines
/// that start with a space (shells keep those out of history too).
class CommandCapture {
  CommandCapture({required this.onCommand, this.onRun});

  /// How far up the prompt is looked for, when the screen scrolled.
  static const searchRows = 30;

  /// Frames to wait for the shell's answer to Enter before keeping what
  /// was read at Enter.
  static const settleFrames = 20;

  final void Function(String command) onCommand;

  /// Also told each command, with the prompt in front of it and the
  /// column where the prompt ends, so the prompt's return can be spotted.
  final void Function(String command, String prompt, int promptCol)? onRun;

  _Line? _line;
  _Pending? _pending;
  String _typed = '';

  /// The current line after the prompt, while one is being typed.
  String get typed => _typed;

  /// Call before any key or text other than Enter goes to the shell.
  void input(ScreenText? screen) {
    _settle();
    if (_line != null || screen == null || !_usable(screen)) return;
    final row = screen.cursorRow, col = screen.cursorCol;
    _line = _Line(
      row: row,
      col: col,
      prompt: col > 0 ? screen.between(row, 0, row, col - 1) : '',
      before: screen.between(row, 0, row, screen.cols - 1),
    );
  }

  /// Ctrl+C, Ctrl+D, a multi-line paste: the line is dropped.
  void cancel() {
    _settle();
    _line = null;
    _typed = '';
  }

  /// Call before Enter goes to the shell.
  void enter(ScreenText? screen) {
    _settle();
    final line = _line;
    _line = null;
    _typed = '';
    if (line == null || screen == null || !_usable(screen)) return;
    final text = _readAt(screen, _find(screen, line, from: screen.cursorRow) ?? line.row, line);
    final echoed = line.echoed || screen.between(line.row, 0, line.row, screen.cols - 1) != line.before;
    _pending = _Pending(line, echoed ? text ?? '' : '', screen.cursorRow, screen.cursorCol, echoed: echoed);
  }

  /// Call with every new frame.
  void onFrame(ScreenText screen) {
    final line = _line;
    if (line != null) {
      if (!_usable(screen)) {
        _line = null;
        _typed = '';
      } else {
        if (!line.echoed && screen.between(line.row, 0, line.row, screen.cols - 1) != line.before) line.echoed = true;
        _typed = _readAt(screen, _find(screen, line, from: screen.cursorRow) ?? line.row, line) ?? '';
      }
    }
    final pending = _pending;
    if (pending == null) return;
    pending.frames++;
    // Enter was answered once the cursor went to a new row, or back to
    // the start of the same row after the screen scrolled.
    final answered = screen.cursorRow != pending.cursorRow || screen.cursorCol < pending.cursorCol;
    if (answered || pending.frames >= settleFrames || !_usable(screen)) {
      final from = answered ? screen.cursorRow - 1 : screen.cursorRow;
      final row = _usable(screen) ? _find(screen, pending.line, from: from) : null;
      _commit(row == null ? null : _readAt(screen, row, pending.line));
    }
  }

  /// Keeps a command still waiting for the shell's answer.
  void flush() => _settle();

  void _settle() {
    if (_pending != null) _commit(null);
  }

  /// Keeps the re-read text when it agrees with what Enter saw (it only
  /// added a late echo or a completion, or dropped a grey suggestion).
  void _commit(String? reread) {
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    final atEnter = pending.text;
    var command = atEnter;
    if (reread != null && reread.isNotEmpty && (!pending.echoed || reread.startsWith(atEnter) || atEnter.startsWith(reread))) command = reread;
    if (command.trim().isEmpty || command.startsWith(' ') || _masked.hasMatch(command)) return;
    onCommand(command.trim());
    onRun?.call(command.trim(), pending.line.prompt, pending.line.col);
  }

  /// Only stars or dots: a password prompt that echoes a mask.
  static final _masked = RegExp(r'^[*•●·\s]+$');

  bool _usable(ScreenText s) => !s.alternateScreen && !s.scrolledBack;

  /// The nearest row at or above [from] that still starts with the prompt.
  int? _find(ScreenText s, _Line line, {required int from}) {
    final top = (from - searchRows).clamp(0, s.rows - 1);
    for (var row = from.clamp(0, s.rows - 1); row >= top; row--) {
      if (line.col == 0 || s.between(row, 0, row, line.col - 1) == line.prompt) return row;
    }
    return null;
  }

  /// The command after the prompt on [row], following wrapped rows.
  String? _readAt(ScreenText s, int row, _Line line) {
    if (row < 0 || row >= s.rows) return null;
    var end = row;
    while (end < s.rows - 1 && s.rowIsFull(end)) {
      end++;
    }
    final text = s.between(row, line.col, end, s.cols - 1);
    final firstLine = text.split('\n').first;
    return firstLine.trimRight();
  }
}
