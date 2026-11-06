import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/selection_look.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme.dart';
import '../../data/app_settings.dart';
import '../../sessions/terminal_controller.dart';
import '../terminal/terminal_painter.dart';

/// A small live picture of a terminal's screen, as it is right now. It is
/// drawn with the real terminal painter at full size and scaled down to
/// fit, so it looks exactly like the terminal, only smaller. Redraws as
/// new output arrives.
class TerminalThumbnail extends StatefulWidget {
  const TerminalThumbnail({super.key, required this.controller, this.height = 132});

  final TerminalController controller;
  final double height;

  @override
  State<TerminalThumbnail> createState() => _TerminalThumbnailState();
}

class _TerminalThumbnailState extends State<TerminalThumbnail> {
  final _cache = LineCache();

  /// The size the picture is drawn at before it is scaled down. Small
  /// enough to stay cheap, big enough for crisp text after scaling.
  static const _drawFontSize = 12.0;

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final settings = store.settings;
    final colors = AppColorsTheme.of(context);
    final family = TerminalFonts.byId(settings, settings.terminalFontId).family;
    final metrics = CellMetrics.measure(family: family, fontSize: _drawFontSize, lineHeight: settings.lineHeight);
    final selectionLook = SelectionLook.of(store.activeTheme);
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(store.activeTheme.background), border: Border.all(color: colors.outline)),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final frame = widget.controller.frame;
              if (frame == null || frame.rows == 0 || frame.cols == 0) return const SizedBox.expand();
              final size = Size(frame.cols * metrics.width, frame.rows * metrics.height);
              return FittedBox(
                // The top of the screen, where a prompt and output start.
                fit: BoxFit.fitWidth,
                alignment: Alignment.topLeft,
                clipBehavior: Clip.hardEdge,
                child: SizedBox.fromSize(
                  size: size,
                  child: CustomPaint(
                    size: size,
                    painter: TerminalPainter(
                      frame: frame,
                      metrics: metrics,
                      cache: _cache,
                      styleKey: (family, _drawFontSize, settings.lineHeight),
                      cursorOn: true,
                      focused: false,
                      cursorStyle: CursorStyle.block,
                      selection: null,
                      selectionLook: selectionLook,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
