import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme.dart';
import '../../app/theme_backgrounds.dart';
import '../../app/theme_spec.dart';
import '../common/widgets.dart';
import 'theme_actions.dart';
import 'theme_text_reader.dart';
import 'theme_text_writer.dart';

/// The whole theme (colours, style and picture list) as commented JSON,
/// for people who like to edit config files. Save checks every value and
/// lists problems by line; tapping one selects that line.
class ThemeTextEditorScreen extends StatefulWidget {
  const ThemeTextEditorScreen({super.key, required this.theme, required this.isNew, required this.pictures});

  final ThemeSpec theme;

  /// True for a copy that is not saved yet (made from a built-in theme).
  final bool isNew;

  /// The pictures in the theme's folder, which "backgrounds" may list.
  final Set<String> pictures;

  @override
  State<ThemeTextEditorScreen> createState() => _ThemeTextEditorScreenState();
}

class _ThemeTextEditorScreenState extends State<ThemeTextEditorScreen> {
  late final _text = TextEditingController(text: ThemeTextWriter.write(widget.theme));
  final _focus = FocusNode();
  List<ThemeTextError> _errors = const [];
  late bool _changed = widget.isNew;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Selects a whole line and moves the cursor there.
  void _goToLine(int line) {
    final text = _text.text;
    var start = 0;
    for (var i = 1; i < line; i++) {
      final next = text.indexOf('\n', start);
      if (next < 0) break;
      start = next + 1;
    }
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    _focus.requestFocus();
    _text.selection = TextSelection(baseOffset: start, extentOffset: end);
  }

  void _save() {
    final result = ThemeTextReader(base: widget.theme, pictures: widget.pictures).read(_text.text);
    if (!result.ok) {
      setState(() => _errors = result.errors);
      _goToLine(result.errors.first.line);
      return;
    }
    final theme = result.theme!;
    final store = AppScope.store(context);
    ThemeActions(context).save(theme, andUse: widget.isNew || store.settings.themeId == theme.id);
    setState(() => _changed = false);
    Toast.show(context, 'Saved ${theme.name}');
    Navigator.pop(context);
  }

  Future<void> _confirmLeave() async {
    final leave = await Confirm.ask(
      context,
      title: widget.isNew ? 'Discard this theme?' : 'Discard changes?',
      message: widget.isNew ? 'The copy has not been saved and will be lost.' : 'Your changes to the text will be lost.',
      action: 'Discard',
    );
    if (!leave || !mounted) return;
    if (widget.isNew) ThemeBackgrounds.deleteFolder(widget.theme.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final mono = Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: TerminalFonts.jetbrains.family, height: 1.4);
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: () => Navigator.maybePop(context)),
          title: const Text('Edit as text'),
        ),
        bottomNavigationBar: _TextSaveBar(onSave: _save),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errors.isNotEmpty) _ErrorList(errors: _errors, onTap: _goToLine),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    // Curly quotes and long dashes would break the JSON.
                    smartQuotesType: SmartQuotesType.disabled,
                    smartDashesType: SmartDashesType.disabled,
                    style: mono?.copyWith(color: colors.text),
                    decoration: const InputDecoration(hintText: 'Theme text'),
                    inputFormatters: [FilteringTextInputFormatter.deny('\t', replacementString: '  ')],
                    onChanged: (_) => setState(() {
                      _changed = true;
                      _errors = const [];
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The problems Save found, each one a button to its line.
class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.errors, required this.onTap});

  final List<ThemeTextError> errors;
  final ValueChanged<int> onTap;

  /// More than this and the text would have no room left.
  static const _shown = 4;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final more = errors.length - _shown;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Color.alphaBlend(colors.danger.withValues(alpha: 0.14), colors.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                errors.length == 1 ? 'One problem stops the save' : '${errors.length} problems stop the save',
                style: text.titleSmall,
              ),
            ),
            for (final error in errors.take(_shown))
              InkWell(
                onTap: () => onTap(error.line),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: colors.danger, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text('$error', style: text.bodyMedium)),
                    ],
                  ),
                ),
              ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('And $more more. Fix these first.', style: text.bodySmall?.copyWith(color: colors.muted)),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Save theme" across the bottom, clear of the gesture bar.
class _TextSaveBar extends StatelessWidget {
  const _TextSaveBar({required this.onSave});

  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: FilledButton(onPressed: onSave, child: const Text('Save theme')),
          ),
        ),
      );
}
