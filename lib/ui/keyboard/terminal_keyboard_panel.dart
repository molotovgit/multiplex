import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme_look.dart';
import '../../app/theme_style.dart';
import '../../sessions/terminal_controller.dart';
import '../history/command_history_sheet.dart';
import '../history/command_strip.dart';
import '../history/command_target.dart';
import 'key_face.dart';
import 'key_sink.dart';
import 'key_spec.dart';
import 'keyboard_engine.dart';
import 'keyboard_layout.dart';
import 'keyboard_modifiers.dart';
import 'keyboard_rows.dart';
import 'keyboard_settings.dart';
import 'keyboard_style.dart';

/// The built-in terminal keyboard: a terminal row (the user's key bar)
/// over letters, numbers and symbols, or function keys. Place it at the
/// bottom of the terminal screen in place of the system keyboard.
class TerminalKeyboardPanel extends StatefulWidget {
  /// The keyboard for a terminal.
  const TerminalKeyboardPanel({
    super.key,
    required TerminalController this.controller,
    required this.onSnippets,
    required this.onHide,
    required this.onSwitchToSystem,
    this.onHistory,
  })  : sink = null,
        onSent = null,
        modifiers = null,
        commands = null;

  /// The keyboard sending somewhere else: the settings preview and tests.
  const TerminalKeyboardPanel.withSink({
    super.key,
    required KeySink this.sink,
    required this.onSnippets,
    required this.onHide,
    required this.onSwitchToSystem,
    this.onSent,
    this.modifiers,
    this.onHistory,
    this.commands = const NoCommandTarget(),
  }) : controller = null;

  final TerminalController? controller;
  final KeySink? sink;
  final VoidCallback onSnippets;
  final VoidCallback onHide;

  /// For voice input or other languages.
  final VoidCallback onSwitchToSystem;

  /// Told what each key sent, in words.
  final ValueChanged<String>? onSent;

  /// Lets tests use a fake clock for double taps.
  final KeyboardModifiers? modifiers;

  /// Opens the command history. When not set, the panel opens the
  /// history sheet itself.
  final VoidCallback? onHistory;

  /// Where recent commands go; the terminal's when not set.
  final CommandTarget? commands;

  @override
  State<TerminalKeyboardPanel> createState() => _TerminalKeyboardPanelState();
}

class _TerminalKeyboardPanelState extends State<TerminalKeyboardPanel> {
  late KeyboardEngine _engine = _newEngine();
  late CommandTarget _commands = _newCommands();

  CommandTarget _newCommands() => widget.commands ?? TerminalCommandTarget(widget.controller!);

  void _openHistory() {
    final open = widget.onHistory;
    if (open != null) {
      open();
    } else {
      CommandHistorySheet.openFor(context, _commands);
    }
  }

  KeyboardEngine _newEngine() => KeyboardEngine(sink: widget.sink ?? ControllerKeySink(widget.controller!), modifiers: widget.modifiers);

  @override
  void didUpdateWidget(TerminalKeyboardPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.sink != widget.sink) {
      final page = _engine.page;
      _engine.dispose();
      _engine = _newEngine()..showPage(page);
    }
    if (old.controller != widget.controller || old.commands != widget.commands) _commands = _newCommands();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final settings = KeyboardSettings.of(store);
    _engine
      ..settings = settings
      ..onSnippets = widget.onSnippets
      ..onHistory = _openHistory
      ..onHide = widget.onHide
      ..onSwitchToSystem = widget.onSwitchToSystem
      ..onSent = widget.onSent;
    final palette = KeyboardPalette.of(context);
    final style = AppStyleTheme.of(context).style;
    final terminalFont = TerminalFonts.byId(store.settings, store.settings.terminalFontId).family;
    final look = KeyLook(
      palette: palette,
      metrics: KeyboardMetrics.resolve(settings, MediaQuery.sizeOf(context), style: style),
      text: KeyTextStyles.of(context, settings, palette, fontFamily: style.keys.labelFont == KeyLabelFont.terminal ? terminalFont : null),
      showHints: settings.showAlternates,
    );
    final layout = KeyboardLayout.of(settings.layout);
    final keyBar = store.settings.keyBar;
    // Keys never take focus: the terminal keeps it, and with it the
    // hardware keyboard.
    return ExcludeFocus(
      child: Material(
        color: palette.panel,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: look.metrics.maxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
                child: ListenableBuilder(
                  listenable: _engine,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (settings.showRecentCommands)
                        CommandStrip(
                          target: _commands,
                          onOpenHistory: _openHistory,
                          compact: look.metrics.rowHeight < CommandStrip.height,
                          // The settings preview has no terminal: show it there.
                          autoHide: _commands is! NoCommandTarget,
                        ),
                      TerminalTopRow(keyBarIds: keyBar, engine: _engine, look: look),
                      _PageKeys(
                        // A new key per page and layout: key states never carry over.
                        key: ValueKey((_engine.page, settings.layout)),
                        rows: layout.page(_engine.page),
                        engine: _engine,
                        look: look,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The five rows of the current page.
class _PageKeys extends StatelessWidget {
  const _PageKeys({super.key, required this.rows, required this.engine, required this.look});

  final List<List<KeySpec>> rows;
  final KeyboardEngine engine;
  final KeyLook look;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final row in rows) KeyRow(keys: row, engine: engine, look: look)],
      );
}
