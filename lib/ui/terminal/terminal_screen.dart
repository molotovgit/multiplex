import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_icons.dart';
import '../../app/app_scope.dart';
import '../../app/screen_awake.dart';
import '../../app/screen_privacy.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../sessions/connect_flow.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/terminal_controller.dart';
import '../../src/rust/api/terminal_types.dart';
import '../appearance/theme_actions.dart';
import '../appearance/theme_switcher.dart';
import '../common/widgets.dart';
import '../files/files_screen.dart';
import '../history/command_history_sheet.dart';
import '../history/command_strip.dart';
import '../history/command_target.dart';
import '../hosts/host_connector.dart';
import '../keyboard/keyboard_settings.dart';
import '../keyboard/terminal_keyboard_panel.dart';
import '../snippets/snippet_blanks_sheet.dart';
import '../snippets/snippets_screen.dart';
import '../tunnels/tunnels_screen.dart';
import '../common/collapsible.dart';
import 'broadcast_banner.dart';
import 'ended_banner.dart';
import 'key_bar.dart';
import 'split_controller.dart';
import 'split_panes.dart';
import 'split_picker.dart';
import 'reconnect_banner.dart';
import 'recording_actions.dart';
import 'search/pane_searches.dart';
import 'search/terminal_search.dart';
import 'search/terminal_search_bar.dart';
import 'terminal_menu.dart';
import 'terminal_tab_strip.dart';
import 'terminal_view.dart';

/// A full-screen terminal with the key bar and the session's actions.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.session, required this.controller});

  final LiveSession session;
  final TerminalController controller;

  /// Opens a new terminal on a session and shows it.
  static Future<void> openNew(BuildContext context, LiveSession session) async {
    final sessions = AppScope.sessions(context);
    try {
      final terminal = await sessions.openTerminal(session);
      if (context.mounted) await open(context, session, terminal);
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not open a terminal: $e');
    }
  }

  static Future<void> open(BuildContext context, LiveSession session, TerminalController terminal) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(session: session, controller: terminal),
      ),
    );
  }

  /// Shows another terminal of the same connection in place of this one,
  /// without a page animation, like switching tabs.
  static void switchTo(BuildContext context, LiveSession session, TerminalController terminal) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => TerminalScreen(session: session, controller: terminal),
      ),
    );
  }

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _focus = FocusNode(debugLabel: 'terminal');

  /// The user switched to the phone's keyboard for this screen (voice
  /// input, another language). Not saved: the next terminal starts with
  /// the built-in keyboard again.
  bool _useSystem = false;

  /// The built-in keyboard is tucked away; a tap on the terminal or the
  /// keyboard button brings it back.
  bool _keyboardHidden = false;

  TerminalController get _terminal => widget.controller;

  /// A second terminal next to this one (landscape and wide screens).
  late final _split = SplitController(primary: widget.controller, primaryFocus: _focus);

  /// The terminal that typing, snippets and picked commands go to: the
  /// focused pane.
  TerminalController get _typing => _split.typing(shown: SplitLayout.of(context));

  /// Find in terminal, one search per pane.
  final _searches = PaneSearches();

  /// The search of the pane that types; its bar shows above the panes.
  TerminalSearch get _search => _searches.of(_typing);

  /// Where picked recent commands go.
  TerminalCommandTarget get _commands => _split.commands(shown: SplitLayout.of(context));

  /// The tab strip shows for a moment when the screen opens, then folds
  /// away so the terminal has the room; a tap on the title brings it back.
  bool _tabsOpen = true;
  Timer? _tabsTimer;

  static const _tabsFor = Duration(seconds: 4);

  void _peekTabs() {
    _tabsTimer?.cancel();
    if (!_tabsOpen) setState(() => _tabsOpen = true);
    _tabsTimer = Timer(_tabsFor, () {
      if (mounted) setState(() => _tabsOpen = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _terminal.shownOnScreen();
    _terminal.onBell = () => HapticFeedback.mediumImpact();
    _terminal.onRemoteCopy = (text) {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) Toast.show(context, 'The server copied text to your clipboard');
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _keepAwake = AppScope.store(context).settings.keepScreenOn;
    if (_keepAwake) ScreenAwake.hold();
    _peekTabs();
  }

  /// Whether this screen asked to keep the display on (released on close).
  bool _keepAwake = false;

  @override
  void dispose() {
    _tabsTimer?.cancel();
    _terminal.leftScreen();
    _searches.dispose();
    _terminal.onBell = null;
    _terminal.onRemoteCopy = null;
    if (_keepAwake) ScreenAwake.release();
    _split.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _keepFocus() {
    final focus = _split.focusNode(shown: SplitLayout.of(context));
    if (!focus.hasFocus) focus.requestFocus();
  }

  /// Picks a terminal for the second pane, or goes back to one pane.
  Future<void> _toggleSplit() async {
    if (_split.isOpen) {
      _split.close();
      return;
    }
    final choice = await SplitPicker.pick(context, current: _terminal);
    if (choice == null || !mounted) return;
    try {
      _split.open(await SplitPicker.resolve(context, choice));
    } catch (e) {
      if (mounted) Toast.show(context, 'Could not open a terminal: $e');
    }
  }

  /// Opens find in `terminal`'s pane, which becomes the one that types.
  /// The search box needs the phone's keyboard; the built-in one makes
  /// room for it until the search closes.
  void _openSearch(TerminalController terminal) {
    _split.focus(second: !identical(terminal, _split.primary));
    _searches.of(terminal).open();
  }

  Future<void> _pickSnippet() async {
    final snippet = await SnippetPicker.show(context);
    if (snippet == null || !mounted) return;
    final command = await SnippetBlanks.fill(context, snippet);
    if (command == null) return;
    _typing.paste(command);
    if (snippet.runImmediately) _typing.key(TerminalKey.enter);
    _keepFocus();
  }

  Future<void> _openHistory() async {
    await CommandHistorySheet.openFor(context, _commands);
    _keepFocus();
  }

  void _changeFontSize(double delta) {
    final store = AppScope.store(context);
    store.updateSettings(store.settings.copyWith(fontSize: store.settings.fontSize + delta));
  }

  Future<void> _closeTerminal() async {
    AppScope.sessions(context).closeTerminal(_terminal);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disconnect() async {
    final ok = await Confirm.ask(
      context,
      title: 'Disconnect from ${widget.session.host.title}?',
      message: 'All terminals and tunnels on this connection will close.',
      action: 'Disconnect',
    );
    if (!ok || !mounted) return;
    await AppScope.sessions(context).disconnect(widget.session);
    if (mounted) Navigator.of(context).pop();
  }

  /// Opens a new connection to the same host after this one dropped.
  Future<void> _reconnect() async {
    final sessions = AppScope.sessions(context);
    final navigator = Navigator.of(context);
    final prompter = HostConnector.prompterFor(context);
    try {
      await sessions.disconnect(widget.session);
      final live = await sessions.connect(widget.session.host, prompter);
      final terminal = await sessions.openTerminal(live);
      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => TerminalScreen(session: live, controller: terminal),
        ),
      );
    } on ConnectCancelled {
      return;
    } catch (e) {
      if (mounted) Toast.show(context, '$e');
    }
  }

  void _switchToSystemKeyboard() {
    setState(() => _useSystem = true);
    // Ask for the phone's keyboard once the text field has its new input
    // type.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keepFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  void _useBuiltInKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _useSystem = false;
      _keyboardHidden = false;
    });
    _keepFocus();
  }

  void _openPage(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final builtIn = KeyboardSettings.of(AppScope.watch(context)).enabled && !_useSystem;
    final tabsByStyle = AppStyleTheme.of(context).style.terminal.showTabs;
    return PrivateScreen(child: ListenableBuilder(
      listenable: Listenable.merge([_terminal, AppScope.sessions(context), _split, _searches]),
      builder: (context, _) {
        // A theme can hide the tabs, but never once there are two terminals
        // to switch between.
        final showTabs = tabsByStyle || widget.session.terminals.length > 1;
        final sessions = AppScope.sessions(context);
        final typing = _typing;
        final visible = _split.visible(shown: SplitLayout.of(context));
        // A pane whose connection is being restored; the typing one first.
        final lost = [typing, ...visible].where((t) => t.reconnecting).firstOrNull;
        final lostSession = lost == null ? null : sessions.byId(lost.sessionId) ?? widget.session;
        final broadcasting = visible.any(sessions.broadcast.includes);
        return Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Semantics(
            button: showTabs,
            hint: showTabs ? 'Shows the tabs' : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: showTabs ? _peekTabs : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_terminal.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  MonoText(widget.session.host.target, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.muted), maxLines: 1),
                ],
              ),
            ),
          ),
          actions: [
            if (KeyboardSettings.of(AppScope.store(context)).enabled && (_useSystem || _keyboardHidden))
              IconButton(tooltip: 'Built-in keyboard', icon: const AppIcon(AppIcons.keyboard), onPressed: _useBuiltInKeyboard),
            // While the tab strip is away its "+" sits here.
            if (!(showTabs && _tabsOpen)) IconButton(tooltip: 'New terminal', icon: const Icon(Icons.add), onPressed: () => TerminalScreen.openNew(context, widget.session)),
            if (SplitLayout.of(context))
              IconButton(
                tooltip: _split.isOpen ? 'Back to one terminal' : 'Split: two terminals side by side',
                icon: Icon(_split.isOpen ? Icons.crop_square : Icons.vertical_split_outlined),
                onPressed: _toggleSplit,
              ),
            for (final pane in visible)
              if (pane.recording) RecordingButton(onStop: () => RecordingActions.toggle(context, pane)),
            IconButton(tooltip: 'Snippets', icon: const AppIcon(AppIcons.snippets), onPressed: _pickSnippet),
            IconButton(
              tooltip: 'Files',
              icon: const AppIcon(AppIcons.folder),
              onPressed: () => _openPage(FilesScreen(session: widget.session)),
            ),
            TerminalMenu(
              onNewTerminal: () => TerminalScreen.openNew(context, widget.session),
              onTunnels: () => _openPage(TunnelsScreen(host: widget.session.host)),
              onCommandHistory: _openHistory,
              onFind: () => _openSearch(_typing),
              onPaste: () => _typing.pasteClipboard(),
              onCopyScreen: () => Toast.copy(context, _terminal.shell.visibleText(), what: 'Screen text copied'),
              onBigger: () => _changeFontSize(1),
              onSmaller: () => _changeFontSize(-1),
              onClearHistory: _terminal.shell.clearHistory,
              recording: typing.recording,
              onRecord: () => RecordingActions.toggle(context, typing),
              onSwitchTheme: () => ThemeSwitcherSheet.show(context),
              onNextBackground: AppScope.store(context).activeTheme.backgrounds.length > 1 ? () => ThemeActions(context).nextBackground() : null,
              onClose: _closeTerminal,
              onDisconnect: _disconnect,
            ),
          ],
        ),
        body: Column(
          children: [
            if (broadcasting) BroadcastBanner(count: sessions.broadcast.size, onStop: sessions.broadcast.stop),
            if (showTabs)
              Collapsible(
                open: _tabsOpen,
                from: Alignment.topCenter,
                child: TerminalTabStrip(
                  session: widget.session,
                  current: _terminal,
                  onSelect: (other) => TerminalScreen.switchTo(context, widget.session, other),
                  onNew: () => TerminalScreen.openNew(context, widget.session),
                ),
              ),
            if (_search.isOpen) TerminalSearchBar(key: ObjectKey(_search), search: _search, onClose: _keepFocus),
            Expanded(
              child: SplitPanes(
                split: _split,
                shown: SplitLayout.of(context),
                paneFor: (terminal, focus) => TerminalView(
                  key: ObjectKey(terminal),
                  controller: terminal,
                  focusNode: focus,
                  search: _searches.of(terminal),
                  onFind: () => _openSearch(terminal),
                  systemKeyboard: !builtIn,
                  onWantsKeyboard: () {
                    if (_keyboardHidden) setState(() => _keyboardHidden = false);
                  },
                ),
              ),
            ),
            if (lost != null && lostSession != null)
              ReconnectBanner(
                note: visible.length > 1 ? '${lost.title}: ${lost.reconnectNote ?? ''}' : lost.reconnectNote ?? '',
                onTryNow: () => lostSession.reconnector?.retryNow(),
                onStop: () => sessions.stopReconnecting(lostSession),
              )
            else if (_terminal.ended)
              EndedBanner(reason: _terminal.endReason ?? '', onReconnect: _reconnect, onClose: _closeTerminal)
            else if (_search.isOpen)
              const SizedBox.shrink()
            else if (builtIn && !_keyboardHidden)
              TerminalKeyboardPanel(
                controller: _typing,
                onSnippets: _pickSnippet,
                onHistory: _openHistory,
                onHide: () => setState(() => _keyboardHidden = true),
                onSwitchToSystem: _switchToSystemKeyboard,
              )
            else if (!builtIn) ...[
              if (KeyboardSettings.of(AppScope.store(context)).showRecentCommands)
                Material(
                  color: colors.surface,
                  child: CommandStrip(target: _commands, onOpenHistory: _openHistory, autoHide: true),
                ),
              KeyBar(controller: _typing, onSnippets: _pickSnippet, keepFocus: _keepFocus),
            ],
          ],
        ),
      );
      },
    ));
  }
}
