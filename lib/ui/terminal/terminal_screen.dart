import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/screen_awake.dart';
import '../../app/theme.dart';
import '../../data/app_settings.dart';
import '../../sessions/connect_flow.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/terminal_controller.dart';
import '../../src/rust/api/terminal_types.dart';
import '../common/widgets.dart';
import '../files/files_screen.dart';
import '../hosts/host_connector.dart';
import '../keyboard/keyboard_settings.dart';
import '../keyboard/terminal_keyboard_panel.dart';
import '../snippets/snippets_screen.dart';
import '../tunnels/tunnels_screen.dart';
import 'key_bar.dart';
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

  @override
  void initState() {
    super.initState();
    _terminal.onBell = () => HapticFeedback.mediumImpact();
    _terminal.onRemoteCopy = (text) {
      Clipboard.setData(ClipboardData(text: text));
      if (mounted) Toast.show(context, 'The server copied text to your clipboard');
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _keepAwake = AppScope.store(context).settings.keepScreenOn;
    if (_keepAwake) ScreenAwake.hold();
  }

  /// Whether this screen asked to keep the display on (released on close).
  bool _keepAwake = false;

  @override
  void dispose() {
    _terminal.onBell = null;
    _terminal.onRemoteCopy = null;
    if (_keepAwake) ScreenAwake.release();
    _focus.dispose();
    super.dispose();
  }

  void _keepFocus() {
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  Future<void> _pickSnippet() async {
    final snippet = await SnippetPicker.show(context);
    if (snippet == null) return;
    _terminal.paste(snippet.command);
    if (snippet.runImmediately) _terminal.key(TerminalKey.enter);
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
    return ListenableBuilder(
      listenable: _terminal,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_terminal.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              MonoText(widget.session.host.target, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.muted), maxLines: 1),
            ],
          ),
          actions: [
            if (KeyboardSettings.of(AppScope.store(context)).enabled && (_useSystem || _keyboardHidden))
              IconButton(tooltip: 'Built-in keyboard', icon: const Icon(Icons.keyboard_outlined), onPressed: _useBuiltInKeyboard),
            IconButton(tooltip: 'Snippets', icon: const Icon(Icons.bolt_outlined), onPressed: _pickSnippet),
            IconButton(
              tooltip: 'Files',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => _openPage(FilesScreen(session: widget.session)),
            ),
            _TerminalMenu(
              onNewTerminal: () => TerminalScreen.openNew(context, widget.session),
              onTunnels: () => _openPage(TunnelsScreen(host: widget.session.host)),
              onPaste: _terminal.pasteClipboard,
              onCopyScreen: () => Toast.copy(context, _terminal.shell.visibleText(), what: 'Screen text copied'),
              onBigger: () => _changeFontSize(1),
              onSmaller: () => _changeFontSize(-1),
              onClearHistory: _terminal.shell.clearHistory,
              onClose: _closeTerminal,
              onDisconnect: _disconnect,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: TerminalView(
                controller: _terminal,
                focusNode: _focus,
                systemKeyboard: !builtIn,
                onWantsKeyboard: () {
                  if (_keyboardHidden) setState(() => _keyboardHidden = false);
                },
              ),
            ),
            if (_terminal.ended)
              _EndedBanner(reason: _terminal.endReason ?? '', onReconnect: _reconnect, onClose: _closeTerminal)
            else if (builtIn && !_keyboardHidden)
              TerminalKeyboardPanel(
                controller: _terminal,
                onSnippets: _pickSnippet,
                onHide: () => setState(() => _keyboardHidden = true),
                onSwitchToSystem: _switchToSystemKeyboard,
              )
            else if (!builtIn)
              KeyBar(controller: _terminal, onSnippets: _pickSnippet, keepFocus: _keepFocus),
          ],
        ),
      ),
    );
  }
}

/// The overflow menu of the terminal screen.
class _TerminalMenu extends StatelessWidget {
  const _TerminalMenu({
    required this.onNewTerminal,
    required this.onTunnels,
    required this.onPaste,
    required this.onCopyScreen,
    required this.onBigger,
    required this.onSmaller,
    required this.onClearHistory,
    required this.onClose,
    required this.onDisconnect,
  });

  final VoidCallback onNewTerminal, onTunnels, onPaste, onCopyScreen, onBigger, onSmaller, onClearHistory, onClose, onDisconnect;

  @override
  Widget build(BuildContext context) {
    final size = AppScope.store(context).settings.fontSize;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'More',
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: onNewTerminal,
          child: const ListTile(leading: Icon(Icons.add), title: Text('New terminal')),
        ),
        PopupMenuItem(
          value: onTunnels,
          child: const ListTile(leading: Icon(Icons.swap_horiz), title: Text('Tunnels')),
        ),
        PopupMenuItem(
          value: onPaste,
          child: const ListTile(leading: Icon(Icons.content_paste), title: Text('Paste')),
        ),
        PopupMenuItem(
          value: onCopyScreen,
          child: const ListTile(leading: Icon(Icons.copy_all), title: Text('Copy screen text')),
        ),
        PopupMenuItem(
          value: onBigger,
          enabled: size < AppSettings.maxFontSize,
          child: ListTile(leading: const Icon(Icons.text_increase), title: Text('Bigger text (${size.round()})')),
        ),
        PopupMenuItem(
          value: onSmaller,
          enabled: size > AppSettings.minFontSize,
          child: const ListTile(leading: Icon(Icons.text_decrease), title: Text('Smaller text')),
        ),
        PopupMenuItem(
          value: onClearHistory,
          child: const ListTile(leading: Icon(Icons.clear_all), title: Text('Clear history')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: onClose,
          child: const ListTile(leading: Icon(Icons.close), title: Text('Close terminal')),
        ),
        PopupMenuItem(
          value: onDisconnect,
          child: const ListTile(leading: Icon(Icons.link_off), title: Text('Disconnect')),
        ),
      ],
    );
  }
}

/// Replaces the key bar once the shell has ended.
class _EndedBanner extends StatelessWidget {
  const _EndedBanner({required this.reason, required this.onReconnect, required this.onClose});

  final String reason;
  final VoidCallback onReconnect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colors.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(reason)),
              TextButton(onPressed: onClose, child: const Text('Close')),
              FilledButton(onPressed: onReconnect, child: const Text('Reconnect')),
            ],
          ),
        ),
      ),
    );
  }
}
