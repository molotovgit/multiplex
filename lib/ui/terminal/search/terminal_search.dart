import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../sessions/terminal_controller.dart';
import '../../../src/rust/api/terminal_types.dart';
import '../terminal_marks.dart';

/// Where a search looks: the terminal, or a fake in tests.
abstract interface class SearchSource {
  /// Every match, oldest first. Lines count from the oldest line of
  /// history (see [SearchMatch]).
  List<SearchMatch> find(String query, {required bool caseSensitive});

  /// Scrolls the view so `line` shows.
  void reveal(int line);
}

/// Searches a [TerminalController]'s screen and scrollback.
class ControllerSearchSource implements SearchSource {
  ControllerSearchSource(this.controller);

  final TerminalController controller;

  @override
  List<SearchMatch> find(String query, {required bool caseSensitive}) => controller.find(query, caseSensitive: caseSensitive);

  @override
  void reveal(int line) => controller.revealLine(line);
}

/// The state of "find in terminal": the bar is open or not, what is typed,
/// the matches, and which one is current. Moving to a match scrolls the
/// view to it.
///
/// New output can move or add matches, so while the bar is open the
/// search runs again shortly after the screen changes ([screenChanged]).
class TerminalSearch extends ChangeNotifier {
  TerminalSearch(this.source, {this.refreshDelay = const Duration(milliseconds: 300)});

  final SearchSource source;

  /// How long to wait after new output before searching again, so a flood
  /// of output does not search on every frame.
  final Duration refreshDelay;

  bool _open = false;
  String _query = '';
  bool _caseSensitive = false;
  List<SearchMatch> _matches = const [];
  int _current = -1;
  Timer? _refresh;

  bool get isOpen => _open;
  String get query => _query;
  bool get caseSensitive => _caseSensitive;
  List<SearchMatch> get matches => _matches;

  /// Index into [matches], or -1 when there is none.
  int get current => _current;

  SearchMatch? get currentMatch => _current < 0 ? null : _matches[_current];

  /// "3 of 12", "No matches", or empty while nothing is typed.
  String get counter {
    if (_query.isEmpty) return '';
    if (_matches.isEmpty) return 'No matches';
    final more = _matches.length >= maxShown ? '+' : '';
    return '${_current + 1} of ${_matches.length}$more';
  }

  /// The native side stops counting here (see `TextSearch::MAX_MATCHES`).
  static const maxShown = 5000;

  void open() {
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    _refresh?.cancel();
    notifyListeners();
  }

  /// A new query. The current match becomes the newest one: what just
  /// scrolled by is usually what the user looks for.
  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _search(keep: false);
  }

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    _search(keep: false);
  }

  /// The next newer match, wrapping round to the oldest.
  void next() => _step(1);

  /// The next older match, wrapping round to the newest.
  void previous() => _step(-1);

  /// Tells the search the screen changed; it searches again soon.
  void screenChanged() {
    if (!_open || _query.isEmpty || (_refresh?.isActive ?? false)) return;
    _refresh = Timer(refreshDelay, () => _search(keep: true));
  }

  /// The matches inside a frame's view, in screen rows.
  List<CellSpan> visibleIn(TerminalFrame frame) => _spans(frame, (i) => i != _current);

  /// The current match, if it is inside the view.
  CellSpan? currentIn(TerminalFrame frame) {
    if (_current < 0) return null;
    final spans = _spans(frame, (i) => i == _current);
    return spans.isEmpty ? null : spans.first;
  }

  List<CellSpan> _spans(TerminalFrame frame, bool Function(int index) wanted) {
    if (!_open || _matches.isEmpty) return const [];
    final top = frame.scrollbackLen - frame.scrollOffset;
    final bottom = top + frame.rows;
    final spans = <CellSpan>[];
    for (var i = _firstAtOrAfter(top); i < _matches.length && _matches[i].line < bottom; i++) {
      if (!wanted(i)) continue;
      final m = _matches[i];
      spans.add(CellSpan(m.line - top, m.col, m.width));
    }
    return spans;
  }

  /// The first match on or below `line` (matches are sorted by line).
  int _firstAtOrAfter(int line) {
    var lo = 0, hi = _matches.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_matches[mid].line < line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _step(int by) {
    if (_matches.isEmpty) return;
    _current = (_current + by) % _matches.length;
    _reveal();
    notifyListeners();
  }

  /// Runs the search. With [keep], the current match stays the same text
  /// at the same place if it is still there.
  void _search({required bool keep}) {
    _refresh?.cancel();
    final before = keep ? currentMatch : null;
    _matches = _query.isEmpty ? const [] : source.find(_query, caseSensitive: _caseSensitive);
    if (_matches.isEmpty) {
      _current = -1;
    } else if (before != null) {
      final same = _matches.indexOf(before);
      _current = same >= 0 ? same : _current.clamp(0, _matches.length - 1);
    } else {
      _current = _matches.length - 1;
      _reveal();
    }
    notifyListeners();
  }

  void _reveal() {
    final m = currentMatch;
    if (m != null) source.reveal(m.line);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }
}
