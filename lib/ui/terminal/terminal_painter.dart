import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';

import '../../app/selection_look.dart';

import '../../data/app_settings.dart';
import '../../src/rust/api/terminal_types.dart';

/// The size of one character cell, measured from the terminal font.
class CellMetrics {
  const CellMetrics({required this.width, required this.height, required this.style});

  final double width;
  final double height;

  /// Base text style (font, size, line height) for drawing runs.
  final TextStyle style;

  /// Measures the cell size of a font. A wide letter gives the advance
  /// every character in a monospace font uses.
  factory CellMetrics.measure({required String? family, required double fontSize, required double lineHeight}) {
    final style = TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      height: lineHeight,
      leadingDistribution: TextLeadingDistribution.even,
      letterSpacing: 0,
    );
    final probe = TextPainter(
      text: TextSpan(text: 'WWWWWWWWWW', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final metrics = CellMetrics(width: probe.width / 10, height: probe.height, style: style);
    probe.dispose();
    return metrics;
  }

  /// How many columns and rows fit in a size.
  (int cols, int rows) gridFor(Size size) => ((size.width / width).floor().clamp(10, 1000), (size.height / height).floor().clamp(4, 500));
}

/// A selected range of cells, in screen coordinates (row, col), both ends
/// included.
class CellSelection {
  const CellSelection(this.anchorRow, this.anchorCol, this.extentRow, this.extentCol);

  final int anchorRow;
  final int anchorCol;
  final int extentRow;
  final int extentCol;

  /// The range ordered from top-left to bottom-right.
  (int, int, int, int) get ordered {
    final anchorFirst = anchorRow < extentRow || (anchorRow == extentRow && anchorCol <= extentCol);
    return anchorFirst ? (anchorRow, anchorCol, extentRow, extentCol) : (extentRow, extentCol, anchorRow, anchorCol);
  }

  CellSelection extendTo(int row, int col) => CellSelection(anchorRow, anchorCol, row, col);
}

/// Keeps laid-out text for lines that did not change, so a frame only lays
/// out the lines that are new. Lines are found by the key the native side
/// gives each line's content.
class LineCache {
  // A map literal keeps insertion order, which the cache uses to drop the
  // least recently used lines first.
  final _lines = <BigInt, List<LaidRun>>{};
  Object? _styleKey;

  /// Throws everything away when the font or size changed.
  void prepare(Object styleKey, int rows) {
    if (_styleKey != styleKey) {
      _clear();
      _styleKey = styleKey;
    }
    // Keep a few screens' worth of lines for scrolling back and forth.
    while (_lines.length > rows * 4) {
      final oldest = _lines.keys.first;
      for (final run in _lines.remove(oldest)!) {
        run.painter.dispose();
      }
    }
  }

  List<LaidRun> lineFor(TerminalLine line, CellMetrics metrics) {
    final cached = _lines.remove(line.key);
    if (cached != null) {
      _lines[line.key] = cached; // most recently used goes last
      return cached;
    }
    final laid = [for (final run in line.runs) LaidRun.layout(run, metrics)];
    _lines[line.key] = laid;
    return laid;
  }

  void _clear() {
    for (final runs in _lines.values) {
      for (final run in runs) {
        run.painter.dispose();
      }
    }
    _lines.clear();
  }

  void dispose() => _clear();
}

/// One run of text, laid out and ready to paint (kept by [LineCache]).
class LaidRun {
  LaidRun(this.run, this.painter);

  final TextRun run;
  final TextPainter painter;

  static const bold = 1, italic = 2, underline = 4;

  factory LaidRun.layout(TextRun run, CellMetrics metrics) {
    final style = metrics.style.copyWith(
      color: Color(run.fg),
      fontWeight: run.style & bold != 0 ? FontWeight.w700 : FontWeight.w400,
      fontStyle: run.style & italic != 0 ? FontStyle.italic : FontStyle.normal,
      decoration: run.style & underline != 0 ? TextDecoration.underline : TextDecoration.none,
      decorationColor: Color(run.fg),
    );
    final painter = TextPainter(
      text: TextSpan(text: run.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return LaidRun(run, painter);
  }
}

/// Paints one terminal frame: backgrounds, text, selection and cursor.
class TerminalPainter extends CustomPainter {
  TerminalPainter({
    required this.frame,
    required this.metrics,
    required this.cache,
    required this.styleKey,
    required this.cursorOn,
    required this.focused,
    required this.cursorStyle,
    required this.selection,
    required this.selectionLook,
    this.paintBackground = true,
  });

  final TerminalFrame frame;
  final CellMetrics metrics;
  final LineCache cache;
  final Object styleKey;

  /// False during the "off" half of a blink.
  final bool cursorOn;
  final bool focused;
  final CursorStyle cursorStyle;
  final CellSelection? selection;
  final SelectionLook selectionLook;

  /// False when a picture shows behind the text: only cells with their
  /// own colour are filled.
  final bool paintBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final w = metrics.width, h = metrics.height;
    if (paintBackground) canvas.drawRect(Offset.zero & size, Paint()..color = Color(frame.background));
    cache.prepare(styleKey, frame.rows);

    final bg = Paint();
    for (var row = 0; row < frame.lines.length; row++) {
      final y = row * h;
      final runs = cache.lineFor(frame.lines[row], metrics);
      for (final laid in runs) {
        if (laid.run.bg != 0) {
          bg.color = Color(laid.run.bg);
          canvas.drawRect(Rect.fromLTWH(laid.run.col * w, y, laid.run.width * w, h), bg);
        }
      }
      final selected = _selectedCells(row);
      if (selected == null) {
        for (final laid in runs) {
          laid.painter.paint(canvas, Offset(laid.run.col * w, y));
        }
      } else {
        _paintSelectedRow(canvas, runs, y, selected);
      }
    }
    _paintCursor(canvas);
  }

  /// The selected columns of a row, both ends included, or null.
  (int, int)? _selectedCells(int row) {
    final sel = selection;
    if (sel == null) return null;
    final (r0, c0, r1, c1) = sel.ordered;
    if (row < r0 || row > r1) return null;
    return (row == r0 ? c0 : 0, row == r1 ? c1 : frame.cols - 1);
  }

  /// Text outside the selection in its own colours; the selection as a
  /// solid fill with its text in the one colour that reads on it.
  void _paintSelectedRow(Canvas canvas, List<LaidRun> runs, double y, (int, int) cells) {
    final w = metrics.width;
    final (from, to) = cells;
    final rect = Rect.fromLTWH(from * w, y, (to - from + 1) * w, metrics.height);
    canvas
      ..save()
      ..clipRect(rect, clipOp: ClipOp.difference);
    for (final laid in runs) {
      laid.painter.paint(canvas, Offset(laid.run.col * w, y));
    }
    canvas
      ..restore()
      ..drawRect(rect, Paint()..color = selectionLook.fill)
      ..save()
      ..clipRect(rect);
    for (final laid in runs) {
      final run = laid.run;
      if (run.col > to || run.col + run.width <= from) continue;
      final style = (laid.painter.text! as TextSpan).style!;
      final painter = TextPainter(
        text: TextSpan(text: run.text, style: style.copyWith(color: selectionLook.text, decorationColor: selectionLook.text)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painter.paint(canvas, Offset(run.col * w, y));
      painter.dispose();
    }
    canvas.restore();
  }

  void _paintCursor(Canvas canvas) {
    final cursor = frame.cursor;
    if (!cursor.visible || cursor.row >= frame.rows) return;
    final w = metrics.width, h = metrics.height;
    final cell = Rect.fromLTWH(cursor.col * w, cursor.row * h, w, h);
    final paint = Paint()..color = Color(cursor.color);
    if (!focused) {
      // Not typing here: a hollow box shows where the cursor is without
      // looking active.
      canvas.drawRect(
        cell.deflate(0.5),
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }
    if (!cursorOn) return;
    // The program's own request wins; our setting applies to the default.
    final shape = switch (cursor.shape) {
      CursorShape.bar => CursorStyle.bar,
      CursorShape.underline => CursorStyle.underline,
      CursorShape.block => cursorStyle,
    };
    switch (shape) {
      case CursorStyle.bar:
        canvas.drawRect(Rect.fromLTWH(cell.left, cell.top, 2, h), paint);
      case CursorStyle.underline:
        canvas.drawRect(Rect.fromLTWH(cell.left, cell.bottom - 2, w, 2), paint);
      case CursorStyle.block:
        canvas.drawRect(cell, paint);
        _paintCharUnderCursor(canvas, cell);
    }
  }

  /// Redraws the character under a block cursor in the background colour
  /// so it stays readable.
  void _paintCharUnderCursor(Canvas canvas, Rect cell) {
    final line = frame.lines[frame.cursor.row];
    for (final run in line.runs) {
      final offset = frame.cursor.col - run.col;
      if (offset < 0 || offset >= run.width) continue;
      final char = run.width == run.text.length ? run.text[offset] : run.text;
      final painter = TextPainter(
        text: TextSpan(
          text: char,
          style: metrics.style.copyWith(color: Color(frame.background)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, cell.topLeft);
      painter.dispose();
      return;
    }
  }

  @override
  bool shouldRepaint(TerminalPainter old) =>
      old.frame != frame ||
      old.styleKey != styleKey ||
      old.cursorOn != cursorOn ||
      old.focused != focused ||
      old.selection != selection ||
      old.selectionLook != selectionLook ||
      old.cursorStyle != cursorStyle ||
      old.paintBackground != paintBackground;
}
