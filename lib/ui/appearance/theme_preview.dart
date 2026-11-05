import 'package:flutter/material.dart';

import '../../app/backdrops/backdrop_painter.dart';
import '../../app/selection_look.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';
import '../../data/app_settings.dart';

/// One piece of text in the fake terminal, with the palette colour it is
/// drawn in.
class PreviewSegment {
  const PreviewSegment(this.text, {this.ansi, this.bold = false, this.selected = false});

  final String text;

  /// Palette index 0-15, or null for the theme's normal text colour.
  final int? ansi;
  final bool bold;

  /// Drawn on the selection colour, like text the user has marked.
  final bool selected;
}

/// What the fake terminal shows: a prompt, a colourful `ls`, an error and
/// a second prompt with the cursor at the end.
abstract final class PreviewScript {
  static const lines = [
    [
      PreviewSegment('user@host', ansi: 2, bold: true),
      PreviewSegment(' '),
      PreviewSegment('~', ansi: 4),
      PreviewSegment(' \$ ls'),
    ],
    [
      PreviewSegment('docs/', ansi: 4, bold: true),
      PreviewSegment('  '),
      PreviewSegment('run.sh', ansi: 2),
      PreviewSegment('  '),
      PreviewSegment('link', ansi: 6),
      PreviewSegment('  '),
      PreviewSegment('logo.png', ansi: 5, selected: true),
    ],
    [PreviewSegment('error: permission denied', ansi: 1)],
    [
      PreviewSegment('~/app', ansi: 4),
      PreviewSegment(' '),
      PreviewSegment('main', ansi: 3),
      PreviewSegment(' \$ '),
    ],
  ];

  /// The title shown on the fake tab, underlined in the accent colour.
  static const tab = 'host';
}

/// A small fake terminal drawn in a theme's own colours. Used in the theme
/// gallery, the theme editor and the font settings.
///
/// Without a [fontSize] the text is scaled to fill the width, which suits
/// gallery cards of any size; the widget then needs a bounded height. With
/// a [fontSize] the text is drawn at exactly that size, the widget is as
/// tall as its lines, and anything too wide is cut off at the edge.
class ThemePreview extends StatelessWidget {
  const ThemePreview({
    super.key,
    required this.theme,
    this.fontFamily,
    this.fontSize,
    this.lineHeight = 1.25,
    this.cursorStyle = CursorStyle.block,
    this.showPalette = true,
    this.borderRadius = BorderRadius.zero,
    this.backdrop,
  });

  final ThemeSpec theme;

  /// Font family to draw in; the bundled Nerd Font when null.
  final String? fontFamily;
  final double? fontSize;
  final double lineHeight;
  final CursorStyle cursorStyle;

  /// Shows all 16 palette colours as a thin strip along the bottom.
  final bool showPalette;
  final BorderRadius borderRadius;

  /// A backdrop drawn faintly behind the text, as in the gallery.
  final BackdropPattern? backdrop;

  /// Size used before scaling when the preview fills its width.
  static const _fitFontSize = 12.0;

  @override
  Widget build(BuildContext context) {
    final fits = fontSize == null;
    final style = TextStyle(
      fontFamily: fontFamily ?? TerminalFonts.jetbrains.family,
      fontSize: fontSize ?? _fitFontSize,
      height: lineHeight,
      color: Color(theme.foreground),
      letterSpacing: 0,
    );
    final lines = _PreviewLines(theme: theme, style: style, cursorStyle: cursorStyle);
    final pad = fits ? 8.0 : 12.0;
    final body = fits
        ? Expanded(
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: FittedBox(fit: BoxFit.fitWidth, alignment: Alignment.topLeft, clipBehavior: Clip.hardEdge, child: lines),
            ),
          )
        : Padding(padding: EdgeInsets.all(pad), child: lines);

    return Semantics(
      label: 'Preview of ${theme.name}',
      image: true,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: borderRadius,
          child: ColoredBox(
            color: Color(theme.background),
            child: CustomPaint(
              painter: backdrop == null ? null : _FaintBackdrop(backdrop!, BackdropColors.of(theme)),
              child: Column(
                mainAxisSize: fits ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  body,
                  if (showPalette) _PaletteStrip(theme: theme, height: fits ? 4 : 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tab title and the terminal lines, one under the other.
class _PreviewLines extends StatelessWidget {
  const _PreviewLines({required this.theme, required this.style, required this.cursorStyle});

  final ThemeSpec theme;
  final TextStyle style;
  final CursorStyle cursorStyle;

  @override
  Widget build(BuildContext context) {
    final last = PreviewScript.lines.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewTab(theme: theme, style: style),
        SizedBox(height: (style.fontSize ?? 12) * 0.4),
        for (var i = 0; i <= last; i++)
          _PreviewLine(
            spans: [
              for (final segment in PreviewScript.lines[i]) _SegmentSpan.of(segment, theme, style),
              if (i == last)
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _PreviewCursor(style: style, shape: cursorStyle, color: Color(theme.cursor)),
                ),
            ],
          ),
      ],
    );
  }
}

/// One terminal line. It never wraps; when there is no room the end is cut
/// off, the way a narrow terminal would.
class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.spans});

  final List<InlineSpan> spans;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        // The terminal draws at its own pixel size, so the preview does too.
        textScaler: TextScaler.noScaling,
      );
}

/// Turns a [PreviewSegment] into styled text.
abstract final class _SegmentSpan {
  static TextSpan of(PreviewSegment segment, ThemeSpec theme, TextStyle base) {
    // Selected text looks as it does in the real terminal.
    final selection = segment.selected ? SelectionLook.of(theme) : null;
    return TextSpan(
      text: segment.text,
      style: base.copyWith(
        color: selection?.text ?? Color(segment.ansi == null ? theme.foreground : theme.ansi[segment.ansi!]),
        fontWeight: segment.bold ? FontWeight.w700 : FontWeight.w400,
        backgroundColor: selection?.fill,
      ),
    );
  }
}

/// A tab title with an accent underline, like the terminal's own tab bar.
class _PreviewTab extends StatelessWidget {
  const _PreviewTab({required this.theme, required this.style});

  final ThemeSpec theme;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final size = style.fontSize ?? 12;
    return Container(
      padding: EdgeInsets.only(left: size * 0.2, right: size * 0.2, bottom: size * 0.15),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(theme.accent), width: (size / 6).clamp(1.5, 3.0))),
      ),
      child: Text(
        PreviewScript.tab,
        maxLines: 1,
        softWrap: false,
        textScaler: TextScaler.noScaling,
        style: style.copyWith(fontWeight: FontWeight.w700, height: 1.1),
      ),
    );
  }
}

/// The cursor in the chosen shape: a filled cell, a thin bar on the left
/// or a line along the bottom, as the real terminal draws it.
class _PreviewCursor extends StatelessWidget {
  const _PreviewCursor({required this.style, required this.shape, required this.color});

  final TextStyle style;
  final CursorStyle shape;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cell = Text(' ', textScaler: TextScaler.noScaling, style: style);
    const width = 2.0;
    return switch (shape) {
      CursorStyle.block => ColoredBox(color: color, child: cell),
      CursorStyle.bar => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: width))),
          child: cell,
        ),
      CursorStyle.underline => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color, width: width))),
          child: cell,
        ),
    };
  }
}

/// All 16 palette colours side by side.
class _PaletteStrip extends StatelessWidget {
  const _PaletteStrip({required this.theme, required this.height});

  final ThemeSpec theme;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Row(
          children: [for (final colour in theme.ansi) Expanded(child: ColoredBox(color: Color(colour)))],
        ),
      );
}

/// A theme's backdrop behind the preview, toned down with the theme's
/// background so the sample text stays clear.
class _FaintBackdrop extends CustomPainter {
  _FaintBackdrop(this.pattern, this.colors);

  final BackdropPattern pattern;
  final BackdropColors colors;

  /// How much of the background colour covers the drawing.
  static const _veil = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    BackdropPainter.of(pattern).paint(canvas, size, colors);
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.background.withValues(alpha: _veil));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FaintBackdrop old) => old.pattern != pattern || old.colors != colors;
}
