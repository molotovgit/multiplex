import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme_spec.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import 'color_picker_dialog.dart';
import 'color_tools.dart';
import 'theme_actions.dart';
import 'theme_editor_parts.dart';
import 'theme_preview.dart';

/// Changes every colour of a theme while a preview shows the result.
/// "Save theme" keeps it as one of the user's themes; Cancel throws the
/// changes away.
class ThemeEditorScreen extends StatefulWidget {
  const ThemeEditorScreen({super.key, required this.theme, this.isNew = false, this.title = 'Edit theme'});

  final ThemeSpec theme;

  /// True for a theme that is not saved yet (new, copied or imported). It
  /// is used as soon as it is saved.
  final bool isNew;
  final String title;

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  late ThemeSpec _draft = widget.theme;
  late final _name = TextEditingController(text: widget.theme.name);
  String? _nameError;

  /// A new theme counts as changed from the start, so leaving asks first.
  late bool _changed = widget.isNew;

  /// Widest the form gets on big screens.
  static const _maxWidth = 720.0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _update(ThemeSpec next) => setState(() {
        _draft = next;
        _changed = true;
      });

  /// Every colour in the draft, offered as quick picks.
  List<int> get _themeColors =>
      [_draft.background, _draft.foreground, _draft.cursor, _draft.accent, ?_draft.selection, ..._draft.ansi];

  Future<ColorPick?> _ask(String title, int current, {String? clearLabel}) =>
      ColorPickerDialog.show(context, title: title, initial: current, suggestions: _themeColors, clearLabel: clearLabel);

  Future<void> _pickMain(String title, int current, ThemeSpec Function(int value) apply) async {
    final pick = await _ask(title, current);
    if (pick?.value != null) _update(apply(pick!.value!));
  }

  Future<void> _pickSelection() async {
    final pick = await _ask('Selection', _draft.selection ?? _draft.accent, clearLabel: 'Use accent');
    if (pick != null) _update(_draft.copyWith(selection: () => pick.value));
  }

  Future<void> _pickAnsi(int index) async {
    final pick = await _ask(AnsiNames.of(index), _draft.ansi[index]);
    if (pick?.value == null) return;
    final ansi = [..._draft.ansi]..[index] = pick!.value!;
    _update(_draft.copyWith(ansi: ansi));
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Give the theme a name.');
      return;
    }
    final store = AppScope.store(context);
    // Built-in themes never change; saving one makes a new theme instead.
    final existing = !widget.isNew && !widget.theme.builtIn && store.customThemes.any((t) => t.id == widget.theme.id);
    final saved = _draft.copyWith(id: existing ? widget.theme.id : VaultStore.newId(), name: name);
    ThemeActions(context).save(saved, andUse: !existing);
    setState(() => _changed = false);
    Toast.show(context, 'Saved ${saved.name}');
    Navigator.pop(context);
  }

  Future<void> _confirmLeave() async {
    final leave = await Confirm.ask(
      context,
      title: widget.isNew ? 'Discard this theme?' : 'Discard changes?',
      message: widget.isNew ? 'The theme has not been saved and will be lost.' : 'Your changes to this theme will be lost.',
      action: 'Discard',
    );
    if (leave && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.store(context).settings;
    final ratio = ColorContrast.ratio(_draft.foreground, _draft.background);
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: () => Navigator.maybePop(context)),
          title: Text(widget.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(onPressed: _save, child: const Text('Save theme')),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: ThemePreview(
                    theme: _draft,
                    fontFamily: TerminalFonts.byId(settings, settings.terminalFontId).family,
                    fontSize: 14,
                    lineHeight: settings.lineHeight,
                    cursorStyle: settings.cursorStyle,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(labelText: 'Name', errorText: _nameError),
                          onChanged: (_) => setState(() {
                            _changed = true;
                            _nameError = null;
                          }),
                        ),
                      ),
                      if (ratio < ColorContrast.lowText)
                        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ContrastWarning(ratio: ratio)),
                      const SectionHeader('Main colours'),
                      ColorRow(
                        label: 'Background',
                        description: 'Behind the terminal text and the app\'s screens',
                        color: _draft.background,
                        onTap: () => _pickMain('Background', _draft.background, (v) => _draft.copyWith(background: v)),
                      ),
                      ColorRow(
                        label: 'Text',
                        description: 'Normal terminal and app text',
                        color: _draft.foreground,
                        onTap: () => _pickMain('Text', _draft.foreground, (v) => _draft.copyWith(foreground: v)),
                      ),
                      ColorRow(
                        label: 'Cursor',
                        description: 'Where typing goes in the terminal',
                        color: _draft.cursor,
                        onTap: () => _pickMain('Cursor', _draft.cursor, (v) => _draft.copyWith(cursor: v)),
                      ),
                      ColorRow(
                        label: 'Accent',
                        description: 'Buttons, tabs and highlights in the app',
                        color: _draft.accent,
                        onTap: () => _pickMain('Accent', _draft.accent, (v) => _draft.copyWith(accent: v)),
                      ),
                      ColorRow(
                        label: 'Selection',
                        description: 'Behind text you mark in the terminal',
                        color: _draft.selection,
                        emptyText: 'Same as accent',
                        onTap: _pickSelection,
                      ),
                      const SectionHeader('Terminal colours'),
                      AnsiColorGrid(ansi: _draft.ansi, onTap: _pickAnsi),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
