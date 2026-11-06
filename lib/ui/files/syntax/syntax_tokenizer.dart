import 'markup_tokenizers.dart';
import 'syntax_language.dart';
import 'syntax_rules.dart';

/// What a coloured piece of text is. Each kind gets one theme colour.
enum SyntaxToken { comment, string, number, keyword, constant, key, variable, heading, error, warning, info, strong, code }

/// Receives one coloured piece: `text[start, end)` is a [SyntaxToken].
typedef TokenSink = void Function(int start, int end, SyntaxToken kind);

/// States a line can end in, carried to the next line.
abstract final class LineState {
  static const normal = 0;
  static const blockComment = 1;
  static const tripleDouble = 2;
  static const tripleSingle = 3;
  static const template = 4;
  static const fence = 5;
}

/// Colours a file one line at a time. A line only needs the state the
/// line before it ended in (inside a comment, a long string...), so the
/// editor can colour just the lines on screen.
abstract class SyntaxTokenizer {
  const SyntaxTokenizer();

  /// True when nothing spans lines, so every line starts in the normal state.
  bool get stateless;

  /// Colours `text[start, end)`, one line without its line break, which
  /// begins in [state]. Returns the state the line ends in.
  int line(String text, int start, int end, int state, TokenSink emit);

  static SyntaxTokenizer? forLanguage(SyntaxLanguage language) => switch (language) {
    SyntaxLanguage.plain => null,
    SyntaxLanguage.markdown => const MarkdownTokenizer(),
    SyntaxLanguage.log => const LogTokenizer(),
    _ => CodeTokenizer(SyntaxRules.of(language)),
  };
}

/// Character tests shared by the tokenizers.
abstract final class Chars {
  static bool isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0D;
  static bool isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool isLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c > 0x7F;
  static bool isWord(int c) => isLetter(c) || isDigit(c);

  /// The first position at or after [i] that is not a space or tab.
  static int skipSpace(String text, int i, int end) {
    while (i < end && isSpace(text.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  /// The end of a quoted string that opened at [i]: just after the closing
  /// quote, or [end] when the line ends first. A backslash escapes the
  /// next character unless [escapes] is off.
  static int closeQuote(String text, int i, int end, int quote, {bool escapes = true}) {
    var j = i + 1;
    while (j < end) {
      final c = text.codeUnitAt(j);
      if (escapes && c == 0x5C) {
        j += 2;
        continue;
      }
      if (c == quote) return j + 1;
      j++;
    }
    return end;
  }

  /// Where [close] next appears at or after [i] before [end], honouring
  /// backslash escapes when asked; -1 when it does not.
  static int find(String text, String close, int i, int end, {bool escapes = false}) {
    var j = i;
    while (j <= end - close.length) {
      final c = text.codeUnitAt(j);
      if (escapes && c == 0x5C) {
        j += 2;
        continue;
      }
      if (text.startsWith(close, j)) return j;
      j++;
    }
    return -1;
  }
}

/// A tokenizer for programming and settings languages, driven by
/// [SyntaxRules]: comments, strings, numbers, keywords, keys, variables.
class CodeTokenizer extends SyntaxTokenizer {
  const CodeTokenizer(this.rules);

  final SyntaxRules rules;

  @override
  bool get stateless => rules.blockComment == null && !rules.tripleQuotes && !rules.templateQuote;

  @override
  int line(String text, int start, int end, int state, TokenSink emit) {
    var i = start;
    if (state != LineState.normal) {
      final (after, still) = _continue(text, i, end, state, emit);
      if (still) return state;
      i = after;
    }
    // Things only found at the start of a line: sections, keys, commands.
    if (i == start) i = _lineStart(text, i, end, emit);
    var statementStart = rules.statementKeywords && i == Chars.skipSpace(text, start, end);
    while (i < end) {
      final c = text.codeUnitAt(i);
      if (Chars.isSpace(c)) {
        i++;
        continue;
      }
      if (_isLineComment(text, i, start)) {
        emit(i, end, SyntaxToken.comment);
        return LineState.normal;
      }
      final block = rules.blockComment;
      if (block != null && text.startsWith(block.$1, i)) {
        final close = Chars.find(text, block.$2, i + block.$1.length, end);
        if (close < 0) {
          emit(i, end, SyntaxToken.comment);
          return LineState.blockComment;
        }
        emit(i, close + block.$2.length, SyntaxToken.comment);
        i = close + block.$2.length;
        continue;
      }
      if (rules.tripleQuotes && (text.startsWith('"""', i) || text.startsWith("'''", i))) {
        final quote = text.substring(i, i + 3);
        final close = Chars.find(text, quote, i + 3, end, escapes: true);
        if (close < 0) {
          emit(i, end, SyntaxToken.string);
          return quote == '"""' ? LineState.tripleDouble : LineState.tripleSingle;
        }
        emit(i, close + 3, SyntaxToken.string);
        i = close + 3;
        continue;
      }
      if (rules.templateQuote && c == 0x60) {
        final close = Chars.find(text, '`', i + 1, end, escapes: true);
        if (close < 0) {
          emit(i, end, SyntaxToken.string);
          return LineState.template;
        }
        emit(i, close + 1, SyntaxToken.string);
        i = close + 1;
        continue;
      }
      if (rules.quotes.codeUnits.contains(c)) {
        // In shell, single quotes take everything literally.
        final close = Chars.closeQuote(text, i, end, c, escapes: !(rules.dollarVariables && c == 0x27));
        emit(i, close, rules.jsonKeys && _colonFollows(text, close, end) ? SyntaxToken.key : SyntaxToken.string);
        i = close;
        statementStart = false;
        continue;
      }
      if (rules.dollarVariables && c == 0x24 && i + 1 < end) {
        i = _variable(text, i, end, emit);
        continue;
      }
      if (rules.yamlKeys && (c == 0x26 || c == 0x2A) && i + 1 < end && Chars.isWord(text.codeUnitAt(i + 1))) {
        // YAML anchors (&base) and aliases (*base).
        var j = i + 1;
        while (j < end && (Chars.isWord(text.codeUnitAt(j)) || text.codeUnitAt(j) == 0x2D)) {
          j++;
        }
        emit(i, j, SyntaxToken.variable);
        i = j;
        continue;
      }
      if (Chars.isDigit(c) && (i == start || !Chars.isWord(text.codeUnitAt(i - 1)))) {
        var j = i + 1;
        while (j < end && (Chars.isWord(text.codeUnitAt(j)) || text.codeUnitAt(j) == 0x2E)) {
          j++;
        }
        emit(i, j, SyntaxToken.number);
        i = j;
        statementStart = false;
        continue;
      }
      if (Chars.isLetter(c)) {
        var j = i + 1;
        while (j < end && (Chars.isWord(text.codeUnitAt(j)) || (rules.wordDash && text.codeUnitAt(j) == 0x2D))) {
          j++;
        }
        final word = text.substring(i, j);
        if (statementStart) {
          emit(i, j, SyntaxToken.keyword);
        } else if (rules.keywords.contains(word)) {
          emit(i, j, SyntaxToken.keyword);
        } else if (rules.constants.contains(rules.caseInsensitiveConstants ? word.toLowerCase() : word)) {
          emit(i, j, SyntaxToken.constant);
        }
        statementStart = false;
        i = j;
        continue;
      }
      // ";", "{" and "}" end an nginx statement; the next word is a directive.
      if (rules.statementKeywords && (c == 0x3B || c == 0x7B || c == 0x7D)) statementStart = true;
      i++;
    }
    return LineState.normal;
  }

  /// Carries on a comment or string from the line above. Returns where it
  /// ended, and whether it is still open at the end of this line.
  (int, bool) _continue(String text, int i, int end, int state, TokenSink emit) {
    final (close, kind, escapes) = switch (state) {
      LineState.blockComment => (rules.blockComment?.$2 ?? '*/', SyntaxToken.comment, false),
      LineState.tripleDouble => ('"""', SyntaxToken.string, true),
      LineState.tripleSingle => ("'''", SyntaxToken.string, true),
      _ => ('`', SyntaxToken.string, true),
    };
    final at = Chars.find(text, close, i, end, escapes: escapes);
    if (at < 0) {
      if (end > i) emit(i, end, kind);
      return (end, true);
    }
    emit(i, at + close.length, kind);
    return (at + close.length, false);
  }

  int _lineStart(String text, int start, int end, TokenSink emit) {
    final i = Chars.skipSpace(text, start, end);
    if (i >= end) return i;
    final c = text.codeUnitAt(i);
    if (rules.sections && c == 0x5B) {
      // "[section]" or TOML's "[[table]]".
      final close = Chars.find(text, ']', i, end);
      final stop = close < 0 ? end : close + 1;
      final double = stop < end && text.codeUnitAt(stop) == 0x5D;
      emit(i, double ? stop + 1 : stop, SyntaxToken.heading);
      return double ? stop + 1 : stop;
    }
    if (rules.assignKeys && !_isLineComment(text, i, start)) {
      final j = _assignKey(text, i, end);
      if (j > i) {
        emit(i, j, SyntaxToken.key);
        return j;
      }
    }
    if (rules.yamlKeys) return _yamlKey(text, i, end, emit);
    final first = rules.firstWordKeywords;
    if (first.isNotEmpty && Chars.isLetter(c)) {
      var j = i;
      while (j < end && Chars.isWord(text.codeUnitAt(j))) {
        j++;
      }
      if (first.contains(text.substring(i, j).toUpperCase())) {
        emit(i, j, SyntaxToken.keyword);
        return j;
      }
    }
    return i;
  }

  /// The end of "key" in "key = value" (spaces before "=" not included),
  /// or [i] when the line is not an assignment.
  int _assignKey(String text, int i, int end) {
    var j = i;
    var last = i;
    while (j < end) {
      final c = text.codeUnitAt(j);
      if (c == 0x3D || (rules.colonAssigns && c == 0x3A)) return last;
      if (!(Chars.isWord(c) || c == 0x2D || c == 0x2E || c == 0x22 || c == 0x27 || Chars.isSpace(c) || c == 0x2F || c == 0x40)) return i;
      j++;
      if (!Chars.isSpace(c)) last = j;
    }
    return i;
  }

  /// YAML: list dashes, then "key:" before a space or the line end.
  int _yamlKey(String text, int i, int end, TokenSink emit) {
    if (text.startsWith('---', i) || text.startsWith('...', i)) {
      emit(i, end, SyntaxToken.comment);
      return end;
    }
    while (i + 1 < end && text.codeUnitAt(i) == 0x2D && Chars.isSpace(text.codeUnitAt(i + 1))) {
      emit(i, i + 1, SyntaxToken.keyword);
      i = Chars.skipSpace(text, i + 1, end);
    }
    var j = i;
    final first = j < end ? text.codeUnitAt(j) : 0;
    if (first == 0x22 || first == 0x27) {
      j = Chars.closeQuote(text, j, end, first);
    } else {
      while (j < end) {
        final c = text.codeUnitAt(j);
        if (c == 0x3A || c == 0x23 || c == 0x7B || c == 0x5B) break;
        j++;
      }
    }
    final colon = j < end && text.codeUnitAt(j) == 0x3A && (j + 1 == end || Chars.isSpace(text.codeUnitAt(j + 1)));
    if (!colon || j == i) return i;
    emit(i, j, SyntaxToken.key);
    return j + 1;
  }

  /// "$HOME", "${name:-x}", "$1", "$?".
  int _variable(String text, int i, int end, TokenSink emit) {
    final next = text.codeUnitAt(i + 1);
    var j = i + 2;
    if (next == 0x7B) {
      final close = Chars.find(text, '}', i + 2, end);
      j = close < 0 ? end : close + 1;
    } else if (next == 0x28) {
      // "$(command)" is code, not a variable: only the "$(" is marked.
      j = i + 2;
    } else if (Chars.isLetter(next)) {
      while (j < end && Chars.isWord(text.codeUnitAt(j))) {
        j++;
      }
    } else if (!Chars.isDigit(next) && !'@*#?\$!-'.codeUnits.contains(next)) {
      return i + 1;
    }
    emit(i, j, SyntaxToken.variable);
    return j;
  }

  bool _isLineComment(String text, int i, int lineStart) {
    for (final prefix in rules.lineComments) {
      if (!text.startsWith(prefix, i)) continue;
      // In shell or YAML, "#" only starts a comment after a space: "a#b" and "${#x}" are not comments.
      if (prefix == '#' && rules.hashNeedsSpace && i > lineStart && !Chars.isSpace(text.codeUnitAt(i - 1))) continue;
      return true;
    }
    return false;
  }

  static bool _colonFollows(String text, int i, int end) {
    final j = Chars.skipSpace(text, i, end);
    return j < end && text.codeUnitAt(j) == 0x3A;
  }
}
