import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A run of cells on one screen row.
@immutable
class CellSpan {
  const CellSpan(this.row, this.col, this.width);

  final int row;
  final int col;

  /// How many cells the span covers.
  final int width;

  /// Whether the cell at `row`, `col` is inside the span.
  bool contains(int row, int col) => row == this.row && col >= this.col && col < this.col + width;

  @override
  bool operator ==(Object other) => other is CellSpan && other.row == row && other.col == col && other.width == width;

  @override
  int get hashCode => Object.hash(row, col, width);

  @override
  String toString() => 'CellSpan($row, $col, $width)';
}

/// Extra marks painted over the terminal text: search matches and the
/// underline of tappable links.
@immutable
class TerminalMarks {
  const TerminalMarks({this.matches = const [], this.current, this.links = const [], required this.accent});

  static const none = TerminalMarks(accent: Color(0x00000000));

  /// Search matches other than the current one.
  final List<CellSpan> matches;

  /// The search match the user is on.
  final CellSpan? current;

  /// Cells of links, URLs and paths, which get a thin underline.
  final List<CellSpan> links;

  /// The theme's accent; the marks are drawn in it.
  final Color accent;

  /// How strongly matches are filled. The current one is stronger, so it
  /// stands out among the rest.
  static const matchAlpha = 0.30, currentAlpha = 0.65;

  /// Links are only hinted at: a soft line, so text full of paths still
  /// reads calmly.
  static const linkAlpha = 0.55;

  bool get isEmpty => matches.isEmpty && current == null;

  /// Fills behind the text of `row`, painted before the text so the
  /// letters stay readable.
  void paintBehind(Canvas canvas, int row, double cellWidth, double cellHeight) {
    if (isEmpty) return;
    final paint = Paint()..color = accent.withValues(alpha: matchAlpha);
    for (final span in matches) {
      if (span.row == row) canvas.drawRect(_rect(span, cellWidth, cellHeight), paint);
    }
    final now = current;
    if (now != null && now.row == row) {
      final rect = _rect(now, cellWidth, cellHeight);
      canvas
        ..drawRect(rect, Paint()..color = accent.withValues(alpha: currentAlpha))
        ..drawRect(
          rect.deflate(0.5),
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
    }
  }

  /// Underlines the links of `row`, painted after the text.
  void paintOver(Canvas canvas, int row, double cellWidth, double cellHeight) {
    if (links.isEmpty) return;
    final paint = Paint()
      ..color = accent.withValues(alpha: linkAlpha)
      ..strokeWidth = 1;
    final y = (row + 1) * cellHeight - 1.5;
    for (final span in links) {
      if (span.row == row) canvas.drawLine(Offset(span.col * cellWidth, y), Offset((span.col + span.width) * cellWidth, y), paint);
    }
  }

  Rect _rect(CellSpan span, double w, double h) => Rect.fromLTWH(span.col * w, span.row * h, span.width * w, h);

  @override
  bool operator ==(Object other) => other is TerminalMarks && listEquals(other.matches, matches) && other.current == current && listEquals(other.links, links) && other.accent == accent;

  @override
  int get hashCode => Object.hash(Object.hashAll(matches), current, Object.hashAll(links), accent);
}
