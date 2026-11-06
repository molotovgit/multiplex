import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/selection_look.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme_look.dart';
import '../../app/theme_slides.dart';
import '../../data/app_settings.dart';
import '../../sessions/terminal_controller.dart';
import '../common/theme_backdrop.dart';
import 'links/link_sheet.dart';
import 'links/screen_links.dart';
import 'search/terminal_search.dart';
import 'terminal_keyboard.dart';
import 'terminal_marks.dart';
import 'terminal_overlays.dart';
import 'terminal_painter.dart';

/// Shows one terminal and turns touch, mouse and keyboard into terminal
/// input.
///
/// - Tap: shows the keyboard (or clicks, in programs that use the mouse).
/// - Drag up and down: scrolls through history, or scrolls inside
///   full-screen programs such as less and vim.
/// - Pinch: changes the font size.
/// - Long press and drag: selects text; a Copy button appears.
class TerminalView extends StatefulWidget {
  const TerminalView({
    super.key,
    required this.controller,
    required this.focusNode,
    this.systemKeyboard = true,
    this.onWantsKeyboard,
    this.search,
    this.onFind,
    this.onOpenPath,
  });

  final TerminalController controller;
  final FocusNode focusNode;

  /// Whether typing uses the phone's keyboard (true) or the built-in one.
  final bool systemKeyboard;

  /// Called when a tap asks for a keyboard, so a hidden built-in keyboard
  /// can come back.
  final VoidCallback? onWantsKeyboard;

  /// Find in terminal; its matches are highlighted.
  final TerminalSearch? search;

  /// Ctrl+Shift+F on a hardware keyboard.
  final VoidCallback? onFind;

  /// Shows a tapped path in the file browser.
  final ValueChanged<String>? onOpenPath;

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  static const _blinkInterval = Duration(milliseconds: 550);

  /// Space around the text, from the theme's style.
  double _padding = 4;

  final _cache = LineCache();
  final _linkFinder = ScreenLinks();

  /// The links on the frame being shown, for taps.
  List<ScreenLink> _links = const [];
  Timer? _blink;
  bool _cursorOn = true;
  CellSelection? _selection;
  double _scrollRemainder = 0;
  double? _pinchStartSize;
  (int, int)? _lastGrid;

  TerminalController get _terminal => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    _restartBlink();
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _blink?.cancel();
    _cache.dispose();
    super.dispose();
  }

  void _onFocusChange() => setState(_restartBlink);

  void _restartBlink() {
    _blink?.cancel();
    _cursorOn = true;
    if (!AppScope.store(context).settings.cursorBlink) return;
    _blink = Timer.periodic(_blinkInterval, (_) {
      if (mounted && widget.focusNode.hasFocus) setState(() => _cursorOn = !_cursorOn);
    });
  }

  /// The cell under a point, clamped to the screen.
  (int row, int col) _cellAt(Offset local, CellMetrics m) {
    final frame = _terminal.frame;
    final rows = frame?.rows ?? 1, cols = frame?.cols ?? 1;
    final row = ((local.dy - _padding) / m.height).floor().clamp(0, rows - 1);
    final col = ((local.dx - _padding) / m.width).floor().clamp(0, cols - 1);
    return (row, col);
  }

  void _showKeyboard() {
    widget.focusNode.requestFocus();
    widget.onWantsKeyboard?.call();
    if (widget.systemKeyboard) SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _onTapUp(TapUpDetails details, CellMetrics m) {
    if (_selection != null) {
      setState(() => _selection = null);
      return;
    }
    final (row, col) = _cellAt(details.localPosition, m);
    // Programs that use the mouse (htop, mc) get the tap, links or not.
    final link = _terminal.frame?.mouseReporting == false ? ScreenLinks.at(_links, row, col) : null;
    if (link != null) {
      HapticFeedback.selectionClick();
      LinkSheet.show(context, link.link, onOpenPath: widget.onOpenPath);
      return;
    }
    if (!_terminal.click(row, col)) _showKeyboard();
  }

  void _scrollBy(double pixels, Offset at, CellMetrics m) {
    _scrollRemainder += pixels;
    final lines = (_scrollRemainder / m.height).truncate();
    if (lines == 0) return;
    _scrollRemainder -= lines * m.height;
    final (row, col) = _cellAt(at, m);
    // Dragging down shows older lines, like any scrolling list.
    _terminal.scroll(lines, row, col);
  }

  void _onScaleStart(ScaleStartDetails details, AppSettings settings) {
    _scrollRemainder = 0;
    _pinchStartSize = details.pointerCount > 1 ? settings.fontSize : null;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, CellMetrics m) {
    if (details.pointerCount > 1 && _pinchStartSize != null) {
      final store = AppScope.store(context);
      final size = (_pinchStartSize! * details.scale).roundToDouble();
      if (size != store.settings.fontSize) store.updateSettings(store.settings.copyWith(fontSize: size));
      return;
    }
    _scrollBy(details.focalPointDelta.dy, details.localFocalPoint, m);
  }

  void _onPointerSignal(PointerSignalEvent event, CellMetrics m) {
    if (event is PointerScrollEvent) _scrollBy(-event.scrollDelta.dy, event.localPosition, m);
  }

  void _startSelection(LongPressStartDetails details, CellMetrics m) {
    final (row, col) = _cellAt(details.localPosition, m);
    HapticFeedback.selectionClick();
    setState(() => _selection = CellSelection(row, col, row, col));
  }

  void _extendSelection(LongPressMoveUpdateDetails details, CellMetrics m) {
    final sel = _selection;
    if (sel == null) return;
    final (row, col) = _cellAt(details.localPosition, m);
    setState(() => _selection = sel.extendTo(row, col));
  }

  Future<void> _copySelection() async {
    final sel = _selection;
    if (sel == null) return;
    final (r0, c0, r1, c1) = sel.ordered;
    final text = _terminal.textBetween(r0, c0, r1, c1);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _selection = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  /// Tells the shell how many cells fit, whenever that changes.
  void _sendGrid(Size size, CellMetrics m) {
    final grid = m.gridFor(Size(size.width - _padding * 2, size.height - _padding * 2));
    if (grid == _lastGrid) return;
    _lastGrid = grid;
    WidgetsBinding.instance.addPostFrameCallback((_) => _terminal.resize(grid.$1, grid.$2));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, _terminal, ?widget.search]),
      builder: (context, _) {
        final settings = store.settings;
        final family = TerminalFonts.byId(settings, settings.terminalFontId).family;
        final metrics = CellMetrics.measure(family: family, fontSize: settings.fontSize, lineHeight: settings.lineHeight);
        final styleKey = (family, settings.fontSize, settings.lineHeight);
        final frame = _terminal.frame;
        final theme = store.activeTheme;
        final selectionLook = SelectionLook.of(theme);
        final style = AppStyleTheme.of(context).style;
        final backdrop = style.backdrop;
        final slide = ActiveSlide.of(theme, settings);
        _padding = style.terminal.padding;
        final search = widget.search;
        final searching = frame != null && search != null && search.isOpen;
        _links = frame == null ? const [] : _linkFinder.of(frame);
        final marks = TerminalMarks(
          matches: searching ? search.visibleIn(frame) : const [],
          current: searching ? search.currentIn(frame) : null,
          links: [for (final link in _links) link.span],
          accent: Color(theme.accent),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            _sendGrid(constraints.biggest, metrics);
            return TerminalKeyboard(
              controller: _terminal,
              focusNode: widget.focusNode,
              systemKeyboard: widget.systemKeyboard,
              onFind: widget.onFind,
              child: Semantics(
                label: 'Terminal',
                hint: 'Tap to type. Tap an underlined link for its actions. Drag to scroll. Long press to select text.',
                child: Listener(
                  onPointerSignal: (e) => _onPointerSignal(e, metrics),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTapUp(d, metrics),
                    onScaleStart: (d) => _onScaleStart(d, settings),
                    onScaleUpdate: (d) => _onScaleUpdate(d, metrics),
                    onLongPressStart: (d) => _startSelection(d, metrics),
                    onLongPressMoveUpdate: (d) => _extendSelection(d, metrics),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ThemeBackdrop(
                            theme: theme,
                            slide: slide,
                            color: Color(frame?.background ?? theme.background),
                            dim: backdrop.dim,
                            blur: backdrop.blur,
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.all(_padding),
                            child: frame == null
                                ? const SizedBox.expand()
                                : CustomPaint(
                                    size: Size.infinite,
                                    painter: TerminalPainter(
                                      frame: frame,
                                      metrics: metrics,
                                      cache: _cache,
                                      styleKey: styleKey,
                                      cursorOn: _cursorOn || !settings.cursorBlink,
                                      focused: widget.focusNode.hasFocus,
                                      cursorStyle: settings.cursorStyle,
                                      selection: _selection,
                                      selectionLook: selectionLook,
                                      paintBackground: slide == null,
                                      marks: marks,
                                    ),
                                  ),
                          ),
                        ),
                        if (frame != null && frame.scrollOffset > 0)
                          JumpToLiveButton(lines: frame.scrollOffset, onPressed: _terminal.scrollToBottom),
                        if (_selection != null) CopyBar(onCopy: _copySelection, onCancel: () => setState(() => _selection = null)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
