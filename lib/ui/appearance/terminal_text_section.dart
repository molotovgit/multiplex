import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme.dart';
import '../../data/app_settings.dart';
import '../common/widgets.dart';
import 'font_library.dart';
import 'theme_preview.dart';

/// Terminal font, text size, line height and cursor. Every change is
/// saved and used at once; the sample at the top shows the result.
///
/// Expects to be rebuilt when the store changes (the Appearance screen
/// wraps it in a ListenableBuilder).
class TerminalTextSection extends StatefulWidget {
  const TerminalTextSection({super.key});

  /// Letters that are easy to mix up, brackets, and Nerd Font glyphs: a
  /// branch sign (U+E0A0) and powerline arrows (U+E0B0, U+E0B2).
  static const sample = 'AaBb 0O 1lI {} =>  main  ';

  @override
  State<TerminalTextSection> createState() => _TerminalTextSectionState();
}

class _TerminalTextSectionState extends State<TerminalTextSection> {
  /// Changes a setting. The store writes it to disk a moment later, so a
  /// slider being dragged does not save on every step.
  void _change(AppSettings Function(AppSettings s) edit) {
    final store = AppScope.store(context);
    store.updateSettings(edit(store.settings));
  }

  Future<void> _addFont() async {
    try {
      final font = await FontLibrary(AppScope.store(context)).addFromFile();
      if (font != null && mounted) Toast.show(context, 'Added ${font.name}');
    } on FontFileException catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (e) {
      if (mounted) Toast.show(context, 'Could not add the font ($e). Try again.');
    }
  }

  Future<void> _removeFont(CustomFont font) async {
    final store = AppScope.store(context);
    final inUse = store.settings.terminalFontId == font.id;
    final ok = await Confirm.ask(
      context,
      title: 'Remove font?',
      message: '"${font.name}" will be removed and its file deleted from this device.'
          '${inUse ? ' The terminal will go back to ${TerminalFonts.jetbrains.name}.' : ''}',
      action: 'Remove font',
    );
    if (!ok || !mounted) return;
    await FontLibrary(store).remove(font);
    if (mounted) Toast.show(context, 'Removed ${font.name}');
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final settings = store.settings;
    final fontSize = settings.fontSize;
    final lineHeight = settings.lineHeight;
    final current = TerminalFonts.byId(settings, settings.terminalFontId);
    final custom = {for (final f in settings.customFonts) f.id: f};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Terminal text'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ThemePreview(
            theme: store.activeTheme,
            fontFamily: current.family,
            fontSize: fontSize,
            lineHeight: lineHeight,
            cursorStyle: settings.cursorStyle,
            showPalette: false,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SectionHeader('Font'),
        for (final font in TerminalFonts.available(settings))
          _FontTile(
            font: font,
            selected: font.id == current.id,
            onTap: () => _change((s) => s.copyWith(terminalFontId: font.id)),
            onRemove: custom.containsKey(font.id) ? () => _removeFont(custom[font.id]!) : null,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: _addFont, icon: const Icon(Icons.add), label: const Text('Add font from file')),
          ),
        ),
        const SectionHeader('Size and spacing'),
        _SettingSlider(
          label: 'Font size',
          value: fontSize,
          min: AppSettings.minFontSize,
          max: AppSettings.maxFontSize,
          divisions: (AppSettings.maxFontSize - AppSettings.minFontSize).round(),
          shown: fontSize.round().toString(),
          onChanged: (v) => _change((s) => s.copyWith(fontSize: v.roundToDouble())),
        ),
        _SettingSlider(
          label: 'Line height',
          value: lineHeight,
          min: AppSettings.minLineHeight,
          max: AppSettings.maxLineHeight,
          divisions: 12,
          shown: lineHeight.toStringAsFixed(2),
          onChanged: (v) => _change((s) => s.copyWith(lineHeight: (v * 20).round() / 20)),
        ),
        const SectionHeader('Cursor'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<CursorStyle>(
            segments: const [
              ButtonSegment(value: CursorStyle.block, label: Text('Block'), icon: Icon(Icons.rectangle)),
              ButtonSegment(value: CursorStyle.bar, label: Text('Bar'), icon: Icon(Icons.text_fields)),
              ButtonSegment(value: CursorStyle.underline, label: Text('Underline'), icon: Icon(Icons.format_underline)),
            ],
            selected: {settings.cursorStyle},
            showSelectedIcon: false,
            onSelectionChanged: (picked) => _change((s) => s.copyWith(cursorStyle: picked.first)),
          ),
        ),
        SwitchListTile(
          title: const Text('Blinking cursor'),
          subtitle: const Text('The cursor flashes while the terminal waits for typing'),
          value: settings.cursorBlink,
          onChanged: (on) => _change((s) => s.copyWith(cursorBlink: on)),
        ),
      ],
    );
  }
}

/// One font to choose: its name, a sample line drawn in it, and for
/// fonts the user added, a button that removes it.
class _FontTile extends StatelessWidget {
  const _FontTile({required this.font, required this.selected, required this.onTap, this.onRemove});

  final TerminalFont font;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? colors.accent : colors.muted),
      title: Text(font.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Text(
            TerminalTextSection.sample,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: text.bodyLarge?.copyWith(fontFamily: font.family, color: colors.text, letterSpacing: 0),
          ),
          if (font.note != null) Text(font.note!, style: text.bodySmall?.copyWith(color: colors.muted)),
        ],
      ),
      trailing: onRemove == null
          ? null
          : IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove ${font.name}', onPressed: onRemove),
    );
  }
}

/// A labelled slider with its current value at the end.
class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.shown,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String shown;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = AppColorsTheme.of(context).muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: shown,
              onChanged: onChanged,
              semanticFormatterCallback: (_) => '$label $shown',
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(shown, textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted)),
          ),
        ],
      ),
    );
  }
}
