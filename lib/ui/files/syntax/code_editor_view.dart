import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/theme.dart';
import 'syntax_controller.dart';

/// A code text area: line numbers down the side, long lines scroll
/// sideways instead of wrapping (unless [wrap] is on), and colours from
/// [SyntaxEditingController] for the lines on screen.
class CodeEditorView extends StatefulWidget {
  const CodeEditorView({
    super.key,
    required this.controller,
    required this.style,
    required this.readOnly,
    required this.wrap,
    required this.semanticLabel,
    this.hint,
    this.padding = const EdgeInsets.fromLTRB(12, 16, 16, 16),
  });

  final SyntaxEditingController controller;

  /// The monospace text style; its font size sets the line height.
  final TextStyle style;
  final bool readOnly;

  /// Wraps long lines to the screen width. Line numbers then hide, as one
  /// line of the file can take several rows on screen.
  final bool wrap;
  final String semanticLabel;
  final String? hint;
  final EdgeInsets padding;

  /// Line height as a multiple of the font size; every line is exactly
  /// this tall, so line numbers stay level with the text.
  static const lineSpacing = 1.45;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _fieldKey = GlobalKey();
  bool _updateQueued = false;
  int _longest = 0;
  int _lineCount = 0;

  /// The height of one line as the text engine lays it out, which can
  /// differ a little from font size times spacing (it rounds).
  double? _measuredLineHeight;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_queueWindowUpdate);
    widget.controller.addListener(_textChanged);
    _longest = widget.controller.lines.longest;
    _lineCount = widget.controller.lines.count;
    _queueWindowUpdate();
  }

  @override
  void didUpdateWidget(CodeEditorView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_textChanged);
      widget.controller.addListener(_textChanged);
    }
    _queueWindowUpdate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_textChanged);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Redraws the frame around the text only when the longest line or the
  /// number of lines changed, not on every key.
  void _textChanged() {
    final lines = widget.controller.lines;
    final changed = lines.longest != _longest || lines.count != _lineCount;
    _longest = lines.longest;
    _lineCount = lines.count;
    if (changed && !widget.wrap) setState(() {});
  }

  /// Works out which lines are on screen once the frame is laid out, at
  /// most once a frame however fast the list scrolls.
  void _queueWindowUpdate() {
    if (_updateQueued) return;
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQueued = false;
      if (mounted) _updateWindow();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _updateWindow() {
    final box = _fieldKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final editable = _findEditable(box);
    final lines = widget.controller.lines;
    if (editable == null) return;
    final measured = editable.preferredLineHeight;
    if (measured != _measuredLineHeight) setState(() => _measuredLineHeight = measured);
    final top = box.localToGlobal(Offset(widget.padding.left + 8, widget.padding.top + 2));
    final bottom = box.localToGlobal(Offset(widget.padding.left + 8, box.size.height - 2));
    final first = editable.getPositionForPoint(top).offset;
    final last = editable.getPositionForPoint(bottom).offset;
    widget.controller.showLines(lines.lineOf(first), lines.lineOf(last));
  }

  static RenderEditable? _findEditable(RenderObject root) {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
      } else {
        child.visitChildren(visit);
      }
    }

    visit(root);
    return found;
  }

  double get _lineHeight => _measuredLineHeight ?? (widget.style.fontSize ?? 14) * CodeEditorView.lineSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final style = widget.style.copyWith(height: CodeEditorView.lineSpacing);
    final field = Semantics(
      label: widget.semanticLabel,
      child: TextField(
        key: _fieldKey,
        controller: widget.controller,
        scrollController: _vertical,
        readOnly: widget.readOnly,
        expands: true,
        maxLines: null,
        minLines: null,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: false,
        enableSuggestions: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        style: style,
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: widget.padding,
          hintText: widget.hint,
        ),
      ),
    );
    if (widget.wrap) return field;
    return LayoutBuilder(
      builder: (context, constraints) {
        final digits = math.max(2, '${widget.controller.lines.count}'.length);
        final charWidth = _CharWidth.of(style);
        final gutterWidth = digits * charWidth + 20;
        final available = math.max(0.0, constraints.maxWidth - gutterWidth);
        // Wide enough for the longest line, plus room for the caret.
        final needed = math.min(_longest, _CharWidth.maxColumns) * charWidth + widget.padding.horizontal + 3 * charWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: gutterWidth,
                child: CustomPaint(
                  painter: LineNumberPainter(
                    scroll: _vertical,
                    lineCount: widget.controller.lines.count,
                    lineHeight: _lineHeight,
                    top: widget.padding.top,
                    bottom: widget.padding.bottom,
                    style: style.copyWith(color: colors.muted),
                    divider: colors.outline,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: math.max(available, needed), height: constraints.maxHeight, child: field),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The width of one character of a monospace style.
abstract final class _CharWidth {
  /// Lines longer than this wrap even with wrapping off, so one huge line
  /// (minified files) cannot make an endless text area.
  static const maxColumns = 4000;

  static final _cache = <TextStyle, double>{};

  static double of(TextStyle style) => _cache.putIfAbsent(style, () {
    final painter = TextPainter(text: TextSpan(text: 'M' * 32, style: style), textDirection: TextDirection.ltr)..layout();
    final width = painter.width / 32;
    painter.dispose();
    return width;
  });
}

/// Draws the numbers of the lines on screen, level with the text, and
/// redraws as the text scrolls.
class LineNumberPainter extends CustomPainter {
  LineNumberPainter({
    required this.scroll,
    required this.lineCount,
    required this.lineHeight,
    required this.top,
    required this.bottom,
    required this.style,
    required this.divider,
  }) : super(repaint: scroll);

  final ScrollController scroll;
  final int lineCount;
  final double lineHeight;
  final double top;
  final double bottom;
  final TextStyle style;
  final Color divider;

  /// Laid-out numbers, kept between frames so scrolling stays smooth.
  static final _painters = <String, TextPainter>{};

  /// The first and last line number drawn in the last paint.
  (int, int) lastDrawn = (0, -1);

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    canvas.drawRect(Rect.fromLTWH(size.width - 1, 0, 1, size.height), Paint()..color = divider);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, top, size.width, size.height - bottom));
    final first = math.max(0, (offset / lineHeight).floor());
    final last = math.min(lineCount - 1, ((offset + size.height) / lineHeight).ceil());
    if (_painters.length > 600) _clearCache();
    for (var line = first; line <= last; line++) {
      final key = '${style.hashCode}:${line + 1}';
      final painter = _painters.putIfAbsent(
        key,
        () => TextPainter(text: TextSpan(text: '${line + 1}', style: style), textDirection: TextDirection.ltr)..layout(),
      );
      final y = top + line * lineHeight - offset + (lineHeight - painter.height) / 2;
      painter.paint(canvas, Offset(size.width - 10 - painter.width, y));
    }
    canvas.restore();
    lastDrawn = (first + 1, last + 1);
  }

  static void _clearCache() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }

  @override
  bool shouldRepaint(LineNumberPainter old) =>
      old.lineCount != lineCount || old.lineHeight != lineHeight || old.style != style || old.top != top || old.scroll != scroll;
}
