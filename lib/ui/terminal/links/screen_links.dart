import '../../../src/rust/api/terminal_types.dart';
import '../terminal_marks.dart';
import 'link_detector.dart';

/// A detected link and the cells it covers on screen.
class ScreenLink {
  const ScreenLink(this.link, this.span);

  final DetectedLink link;
  final CellSpan span;
}

/// The text of one screen row, rebuilt from its runs, with the cells each
/// character covers so a find in the text can be turned into cells.
class RowText {
  RowText._(this.text, this._starts, this._ends);

  /// Lays the runs out at their columns; gaps (trimmed spaces) become
  /// spaces again.
  factory RowText.of(TerminalLine line) {
    final text = StringBuffer();
    final starts = <int>[], ends = <int>[];
    var col = 0;
    for (final run in line.runs) {
      while (col < run.col) {
        text.write(' ');
        starts.add(col);
        ends.add(++col);
      }
      if (run.text.length == run.width) {
        // Plain text: one character per cell.
        for (var i = 0; i < run.text.length; i++) {
          starts.add(run.col + i);
          ends.add(run.col + i + 1);
        }
      } else {
        // One character (maybe wide, maybe with marks) over the whole run.
        for (var i = 0; i < run.text.length; i++) {
          starts.add(run.col);
          ends.add(run.col + run.width);
        }
      }
      text.write(run.text);
      col = run.col + run.width;
    }
    return RowText._(text.toString(), starts, ends);
  }

  final String text;
  final List<int> _starts;
  final List<int> _ends;

  /// The cells of `text[start..end)` on screen row `row`.
  CellSpan span(int row, int start, int end) => CellSpan(row, _starts[start], _ends[end - 1] - _starts[start]);
}

/// Finds the links on screen, remembering the answer for rows that did
/// not change (rows are told apart by the key the native side gives
/// their content).
class ScreenLinks {
  final _byLine = <BigInt, List<(DetectedLink, int col, int width)>>{};

  /// Enough rows for a few screens of scrolling back and forth.
  static const _keep = 600;

  List<ScreenLink> of(TerminalFrame frame) {
    final found = <ScreenLink>[];
    for (var row = 0; row < frame.lines.length; row++) {
      final line = frame.lines[row];
      final cached = _byLine.remove(line.key) ?? _detect(line);
      _byLine[line.key] = cached; // most recently used goes last
      for (final (link, col, width) in cached) {
        found.add(ScreenLink(link, CellSpan(row, col, width)));
      }
    }
    while (_byLine.length > _keep) {
      _byLine.remove(_byLine.keys.first);
    }
    return found;
  }

  List<(DetectedLink, int, int)> _detect(TerminalLine line) {
    if (line.runs.isEmpty) return const [];
    final row = RowText.of(line);
    return [for (final link in LinkDetector.find(row.text)) _placed(row, link)];
  }

  static (DetectedLink, int, int) _placed(RowText row, DetectedLink link) {
    final span = row.span(0, link.start, link.end);
    return (link, span.col, span.width);
  }

  /// The link under a cell, if any.
  static ScreenLink? at(List<ScreenLink> links, int row, int col) {
    for (final link in links) {
      if (link.span.contains(row, col)) return link;
    }
    return null;
  }
}
