import 'syntax_tokenizer.dart';

/// Markdown: headings, lists, quotes, code blocks and inline code, bold
/// text and links.
class MarkdownTokenizer extends SyntaxTokenizer {
  const MarkdownTokenizer();

  @override
  bool get stateless => false;

  @override
  int line(String text, int start, int end, int state, TokenSink emit) {
    final i = Chars.skipSpace(text, start, end);
    final fence = text.startsWith('```', i) || text.startsWith('~~~', i);
    if (state == LineState.fence) {
      if (end > start) emit(start, end, SyntaxToken.code);
      return fence ? LineState.normal : LineState.fence;
    }
    if (fence) {
      emit(start, end, SyntaxToken.code);
      return LineState.fence;
    }
    if (i >= end) return LineState.normal;
    final c = text.codeUnitAt(i);
    if (c == 0x23) {
      var j = i;
      while (j < end && text.codeUnitAt(j) == 0x23) {
        j++;
      }
      if (j == end || Chars.isSpace(text.codeUnitAt(j))) {
        emit(i, end, SyntaxToken.heading);
        return LineState.normal;
      }
    }
    if (c == 0x3E) {
      emit(i, end, SyntaxToken.comment);
      return LineState.normal;
    }
    var at = i;
    // List markers: "- ", "* ", "+ ", "1. ".
    if ((c == 0x2D || c == 0x2A || c == 0x2B) && i + 1 < end && Chars.isSpace(text.codeUnitAt(i + 1))) {
      emit(i, i + 1, SyntaxToken.keyword);
      at = i + 1;
    } else if (Chars.isDigit(c)) {
      var j = i;
      while (j < end && Chars.isDigit(text.codeUnitAt(j))) {
        j++;
      }
      if (j + 1 < end && (text.codeUnitAt(j) == 0x2E || text.codeUnitAt(j) == 0x29) && Chars.isSpace(text.codeUnitAt(j + 1))) {
        emit(i, j + 1, SyntaxToken.keyword);
        at = j + 1;
      }
    }
    _inline(text, at, end, emit);
    return LineState.normal;
  }

  void _inline(String text, int i, int end, TokenSink emit) {
    while (i < end) {
      final c = text.codeUnitAt(i);
      if (c == 0x60) {
        final close = Chars.find(text, '`', i + 1, end);
        if (close < 0) return;
        emit(i, close + 1, SyntaxToken.code);
        i = close + 1;
        continue;
      }
      if ((c == 0x2A || c == 0x5F) && i + 1 < end && text.codeUnitAt(i + 1) == c) {
        final mark = String.fromCharCodes([c, c]);
        final close = Chars.find(text, mark, i + 2, end);
        if (close > i + 2) {
          emit(i, close + 2, SyntaxToken.strong);
          i = close + 2;
          continue;
        }
      }
      if (c == 0x5B) {
        // [text](address)
        final close = Chars.find(text, '](', i + 1, end);
        final paren = close < 0 ? -1 : Chars.find(text, ')', close + 2, end);
        if (paren > 0) {
          emit(i, close + 1, SyntaxToken.key);
          emit(close + 1, paren + 1, SyntaxToken.string);
          i = paren + 1;
          continue;
        }
      }
      i++;
    }
  }
}

/// Log files: the time at the start of a line, severity words (ERROR,
/// WARN, INFO, DEBUG), quoted text and numbers.
class LogTokenizer extends SyntaxTokenizer {
  const LogTokenizer();

  @override
  bool get stateless => true;

  static final _isoTime = RegExp(r'\[?\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}([.,]\d+)?(Z|[+-]\d{2}:?\d{2})?\]?');
  static final _syslogTime = RegExp(r'[A-Z][a-z]{2} [ \d]\d \d{2}:\d{2}:\d{2}');
  static final _bracketTime = RegExp(r'\[[^\]\n]{0,40}\d{2}:\d{2}:\d{2}[^\]\n]{0,20}\]');

  static const _errors = {'ERROR', 'ERR', 'FATAL', 'CRIT', 'CRITICAL', 'EMERG', 'ALERT', 'FAIL', 'FAILED', 'FAILURE', 'PANIC', 'SEVERE'};
  static const _warnings = {'WARN', 'WARNING'};
  static const _infos = {'INFO', 'NOTICE', 'OK', 'SUCCESS'};
  static const _debugs = {'DEBUG', 'TRACE', 'VERBOSE'};

  @override
  int line(String text, int start, int end, int state, TokenSink emit) {
    var i = start;
    for (final time in [_isoTime, _syslogTime, _bracketTime]) {
      final match = time.matchAsPrefix(text, i);
      if (match != null && match.end <= end) {
        emit(i, match.end, SyntaxToken.comment);
        i = match.end;
        break;
      }
    }
    while (i < end) {
      final c = text.codeUnitAt(i);
      if (c == 0x22) {
        final close = Chars.closeQuote(text, i, end, c);
        emit(i, close, SyntaxToken.string);
        i = close;
        continue;
      }
      if (Chars.isLetter(c)) {
        var j = i + 1;
        while (j < end && Chars.isWord(text.codeUnitAt(j))) {
          j++;
        }
        final kind = _severity(text.substring(i, j));
        if (kind != null) emit(i, j, kind);
        i = j;
        continue;
      }
      if (Chars.isDigit(c) && (i == start || !Chars.isWord(text.codeUnitAt(i - 1)))) {
        var j = i + 1;
        while (j < end && (Chars.isDigit(text.codeUnitAt(j)) || text.codeUnitAt(j) == 0x2E || text.codeUnitAt(j) == 0x3A)) {
          j++;
        }
        emit(i, j, SyntaxToken.number);
        i = j;
        continue;
      }
      i++;
    }
    return LineState.normal;
  }

  /// Severity words count in upper case ("ERROR") and in lower case only
  /// for the common few ("error:", "failed"), so ordinary prose stays plain.
  static SyntaxToken? _severity(String word) {
    if (word.length < 2 || word.length > 9) return null;
    final upper = word.toUpperCase();
    final exact = word == upper || word == 'error' || word == 'failed' || word == 'fatal' || word == 'warning' || word == 'panic';
    if (!exact) return null;
    if (_errors.contains(upper)) return SyntaxToken.error;
    if (_warnings.contains(upper)) return SyntaxToken.warning;
    if (_infos.contains(upper)) return SyntaxToken.info;
    if (_debugs.contains(upper)) return SyntaxToken.comment;
    return null;
  }
}
