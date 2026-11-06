import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'syntax_language.dart';
import 'syntax_palette.dart';
import 'syntax_tokenizer.dart';

/// Where each line of a text starts, for quick "which line is this" look-ups.
class LineIndex {
  LineIndex(String text) {
    var at = 0;
    var longest = 0;
    while (true) {
      final next = text.indexOf('\n', at);
      final end = next < 0 ? text.length : next;
      longest = math.max(longest, end - at);
      _starts.add(at);
      if (next < 0) break;
      at = next + 1;
    }
    _length = text.length;
    this.longest = longest;
  }

  final List<int> _starts = [];
  late final int _length;

  /// Characters in the longest line.
  late final int longest;

  int get count => _starts.length;
  int start(int line) => _starts[line];

  /// Where [line] ends, before its line break.
  int end(int line) => line + 1 < _starts.length ? _starts[line + 1] - 1 : _length;

  /// The line that holds character [offset].
  int lineOf(int offset) {
    var lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// A text controller that colours code. To stay quick on big files it
/// only colours the lines around what is on screen ([showLines]); the
/// rest is drawn plain until it scrolls into view.
class SyntaxEditingController extends TextEditingController {
  SyntaxEditingController({super.text});

  /// Lines coloured above and below the visible ones, so a short scroll
  /// does not show plain text.
  static const margin = 120;

  SyntaxTokenizer? _tokenizer;
  SyntaxLanguage _language = SyntaxLanguage.plain;
  SyntaxPalette? _palette;
  int _windowStart = 0;
  int _windowEnd = 2 * margin;
  LineIndex? _lines;

  /// The state each line starts in; valid for lines up to [_statesValid].
  final List<int> _states = [LineState.normal];

  SyntaxLanguage get language => _language;

  set language(SyntaxLanguage value) {
    if (value == _language) return;
    _language = value;
    _tokenizer = SyntaxTokenizer.forLanguage(value);
    _resetStates();
    notifyListeners();
  }

  set palette(SyntaxPalette value) {
    _palette = value;
    notifyListeners();
  }

  /// The first and last coloured line.
  (int, int) get window => (_windowStart, _windowEnd);

  LineIndex get lines => _lines ??= LineIndex(text);

  /// Makes sure lines [first] to [last] are coloured. Redraws only when
  /// they are not already, so scrolling inside the window costs nothing.
  void showLines(int first, int last) {
    if (first >= _windowStart && last <= _windowEnd) return;
    _windowStart = math.max(0, first - margin);
    _windowEnd = last + margin;
    if (_tokenizer != null) notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    final old = super.value.text;
    if (newValue.text != old) _textChanged(old, newValue.text);
    super.value = newValue;
  }

  /// Line states after the first changed line are no longer right.
  void _textChanged(String old, String now) {
    final lines = _lines;
    _lines = null;
    if (lines == null) {
      _resetStates();
      return;
    }
    final shortest = math.min(old.length, now.length);
    var same = 0;
    while (same < shortest && old.codeUnitAt(same) == now.codeUnitAt(same)) {
      same++;
    }
    final keep = math.min(lines.lineOf(same), _states.length - 1);
    _states.length = keep + 1;
  }

  void _resetStates() => _states
    ..clear()
    ..add(LineState.normal);

  int _stateAt(String text, LineIndex lines, int line) {
    final tokenizer = _tokenizer!;
    if (tokenizer.stateless) return LineState.normal;
    while (_states.length <= line) {
      final i = _states.length - 1;
      _states.add(tokenizer.line(text, lines.start(i), lines.end(i), _states[i], _ignore));
    }
    return _states[line];
  }

  static void _ignore(int start, int end, SyntaxToken kind) {}

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final tokenizer = _tokenizer;
    final palette = _palette;
    final text = this.text;
    if (tokenizer == null || palette == null || text.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final lines = this.lines;
    final first = math.min(_windowStart, lines.count - 1);
    final last = math.min(_windowEnd, lines.count - 1);
    final composing = withComposing && value.isComposingRangeValid ? value.composing : TextRange.empty;
    final spans = _SpanList(text, style, composing);
    var state = _stateAt(text, lines, first);
    var at = lines.start(first);
    spans.add(0, at, null);
    for (var line = first; line <= last; line++) {
      state = tokenizer.line(text, lines.start(line), lines.end(line), state, (start, end, kind) {
        if (start < at) return;
        spans.add(at, start, null);
        spans.add(start, end, palette.style(kind));
        at = end;
      });
      if (!tokenizer.stateless && line + 1 == _states.length) _states.add(state);
    }
    spans.add(at, text.length, null);
    return TextSpan(style: style, children: spans.children);
  }
}

/// Builds the pieces of coloured text, underlining the part the keyboard
/// is still composing, as a plain text field does.
class _SpanList {
  _SpanList(this.text, this.base, this.composing);

  final String text;
  final TextStyle? base;
  final TextRange composing;
  final List<TextSpan> children = [];

  static const _underline = TextStyle(decoration: TextDecoration.underline);

  void add(int start, int end, TextStyle? style) {
    if (end <= start) return;
    if (!composing.isValid || end <= composing.start || start >= composing.end) {
      children.add(TextSpan(text: text.substring(start, end), style: style));
      return;
    }
    final a = math.max(start, composing.start), b = math.min(end, composing.end);
    if (a > start) children.add(TextSpan(text: text.substring(start, a), style: style));
    children.add(TextSpan(text: text.substring(a, b), style: (style ?? const TextStyle()).merge(_underline)));
    if (end > b) children.add(TextSpan(text: text.substring(b, end), style: style));
  }
}
