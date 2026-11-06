import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../sessions/session_manager.dart';
import '../../src/rust/api/sftp.dart';
import '../common/widgets.dart';
import 'file_format.dart';
import 'files_widgets.dart';
import 'folder_browser.dart';
import 'syntax/code_editor_view.dart';
import 'syntax/syntax_controller.dart';
import 'syntax/syntax_language.dart';
import 'syntax/syntax_palette.dart';

/// Opens a small text file from the server, lets the user change it, and
/// writes it back. Warns before leaving with unsaved changes. Code and
/// settings files are coloured in the terminal theme's colours.
class FileEditorScreen extends StatefulWidget {
  const FileEditorScreen({super.key, required this.session, required this.files, required this.path, required this.name});

  /// Files up to this size open here; bigger ones are offered as downloads.
  static const maxBytes = 1024 * 1024;

  final LiveSession session;
  final RemoteFiles files;
  final String path;
  final String name;

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  final _text = SyntaxEditingController();
  ConnectionWatch? _connection;

  /// Long lines wrap instead of scrolling sideways.
  bool _wrap = false;

  /// The text as it is on the server, to tell whether anything changed.
  String _saved = '';
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _dirty = false;

  /// True for files that are not plain text: saving them from here
  /// would damage them, so they open read-only.
  bool _readOnly = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connection ??= ConnectionWatch(widget.session, AppScope.sessions(context));
    _text.palette = SyntaxPalette.fromTheme(AppScope.store(context).activeTheme);
  }

  @override
  void dispose() {
    _text.dispose();
    _connection?.dispose();
    super.dispose();
  }

  /// Redraws only when the "unsaved" state flips, not on every key.
  void _changed() {
    final dirty = !_loading && _text.text != _saved;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final text = await widget.files.readText(path: widget.path, maxBytes: BigInt.from(FileEditorScreen.maxBytes));
      if (!mounted) return;
      _saved = text;
      _readOnly = TextCheck.looksBinary(text);
      final newline = text.indexOf('\n');
      _text.language = _readOnly ? SyntaxLanguage.plain : SyntaxDetect.forFile(widget.path, firstLine: newline < 0 ? text : text.substring(0, newline));
      _text.text = text;
      // A file with very long lines (minified code, one-line JSON) reads
      // better wrapped.
      _wrap = _text.lines.longest > 1000;
      setState(() => _loading = false);
    } catch (error) {
      _connection?.check();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = FileErrors.message(error);
      });
    }
  }

  Future<void> _save() async {
    if (!_dirty || _saving || _readOnly || !(_connection?.value ?? false)) return;
    final text = _text.text;
    setState(() => _saving = true);
    try {
      await widget.files.writeText(path: widget.path, text: text);
      _saved = text;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = _text.text != _saved;
      });
      Toast.show(context, 'Saved ${widget.name}');
    } catch (error) {
      _connection?.check();
      if (!mounted) return;
      setState(() => _saving = false);
      Toast.show(context, 'Could not save "${widget.name}". ${FileErrors.message(error)} Your changes are still here, so you can try again.');
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await Confirm.ask(
      context,
      title: 'Discard changes?',
      message: 'You changed "${widget.name}" but did not save it. Leaving now throws those changes away.',
      action: 'Discard changes',
    );
    if (!leave || !mounted) return;
    setState(() => _dirty = false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final connection = _connection!;
    final colors = AppColorsTheme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: connection,
      builder: (context, connected, _) {
        final canSave = connected && _dirty && !_saving && !_readOnly && !_loading;
        return PopScope(
          canPop: !_dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save, const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save},
            child: Scaffold(
              appBar: AppBar(
                actions: [if (!_loading && _loadError == null) _EditorMenu(controller: _text, wrap: _wrap, onWrap: () => setState(() => _wrap = !_wrap))],
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_dirty ? '${widget.name} (not saved)' : widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    MonoText(widget.path, maxLines: 1, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
                  ],
                ),
              ),
              // The one main action, in thumb reach. It only shows when
              // there is something to save, and rides above the keyboard.
              floatingActionButton: canSave || _saving
                  ? FloatingActionButton.extended(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onAccent))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving' : 'Save'),
                    )
                  : null,
              body: SafeArea(
                top: false,
                child: FilesWidth(
                  child: Column(
                    children: [
                      if (!connected)
                        const ConnectionLostBanner(message: 'The connection to this server closed, so changes cannot be saved. Copy anything you need first.'),
                      if (_readOnly)
                        const NoticeBanner(
                          icon: Icons.lock_outline,
                          message: 'This file is not plain text, so it opens read-only. Saving it from here would damage it. Download it to work with it on this device.',
                        ),
                      Expanded(
                        child: _EditorBody(
                          loading: _loading,
                          error: _loadError,
                          name: widget.name,
                          controller: _text,
                          wrap: _wrap,
                          readOnly: _readOnly || !connected,
                          onRetry: connected ? _load : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The text area, or a spinner or error while there is no text yet.
class _EditorBody extends StatelessWidget {
  const _EditorBody({required this.loading, required this.error, required this.name, required this.controller, required this.wrap, required this.readOnly, this.onRetry});

  final bool loading;
  final String? error;
  final String name;
  final SyntaxEditingController controller;
  final bool wrap;
  final bool readOnly;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return BusyMessage('Opening $name');
    final problem = error;
    if (problem != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not open "$name"',
        message: problem,
        actionLabel: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );
    }
    return CodeEditorView(
      controller: controller,
      style: MonoStyle.of(context) ?? const TextStyle(fontSize: 14),
      readOnly: readOnly,
      wrap: wrap,
      semanticLabel: 'Contents of $name',
      hint: 'This file is empty. Type to add text.',
      // Extra room at the bottom so the Save button never hides the last lines.
      padding: const EdgeInsets.fromLTRB(12, 16, 16, FilesLayout.listBottomPadding),
    );
  }
}

/// The editor's menu: wrap long lines, and which colours to use.
class _EditorMenu extends StatelessWidget {
  const _EditorMenu({required this.controller, required this.wrap, required this.onWrap});

  final SyntaxEditingController controller;
  final bool wrap;
  final VoidCallback onWrap;

  Future<void> _pickLanguage(BuildContext context) async {
    final picked = await showDialog<SyntaxLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Colour as'),
        children: [
          for (final language in SyntaxLanguage.values)
            ListTile(
              leading: Icon(language == controller.language ? Icons.check : null),
              title: Text(language.label),
              selected: language == controller.language,
              onTap: () => Navigator.pop(context, language),
            ),
        ],
      ),
    );
    if (picked != null) controller.language = picked;
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Editor options',
      onSelected: (item) => item == 0 ? onWrap() : _pickLanguage(context),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(value: 0, checked: wrap, child: const Text('Wrap long lines')),
        PopupMenuItem(value: 1, child: Text('Colours: ${controller.language.label}')),
      ],
    );
  }
}

/// Simple checks on text that came from the server.
abstract final class TextCheck {
  /// Text with zero bytes or bytes that are not valid UTF-8 (shown as the
  /// replacement character) is almost certainly not plain text.
  static bool looksBinary(String text) => text.contains('\u0000') || text.contains('\uFFFD');
}
