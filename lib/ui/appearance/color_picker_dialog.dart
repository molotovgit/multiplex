import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import 'color_tools.dart';

/// What the colour dialog returns. [value] is null when the user chose
/// to have no colour of their own (only offered for optional colours).
class ColorPick {
  const ColorPick(this.value);

  final int? value;
}

/// Lets the user choose one colour: type a hex code, move the hue,
/// saturation and lightness sliders, or tap one of the theme's colours.
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({super.key, required this.title, required this.initial, required this.suggestions, this.clearLabel});

  final String title;
  final int initial;

  /// The theme's own colours, offered as quick picks.
  final List<int> suggestions;

  /// When set, a button with this text clears the colour.
  final String? clearLabel;

  /// Opens the dialog. Returns null when the user cancels.
  static Future<ColorPick?> show(
    BuildContext context, {
    required String title,
    required int initial,
    required List<int> suggestions,
    String? clearLabel,
  }) =>
      showDialog<ColorPick>(
        context: context,
        builder: (_) => ColorPickerDialog(title: title, initial: initial, suggestions: suggestions, clearLabel: clearLabel),
      );

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int _value = 0xFF000000 | widget.initial;

  // Kept apart from [_value] so the hue stays put while the colour is grey.
  late HSLColor _hsl = HSLColor.fromColor(Color(_value));
  late final _hex = TextEditingController(text: ColorHex.format(_value));
  String? _hexError;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsl(HSLColor hsl) => setState(() {
        _hsl = hsl;
        _value = hsl.toColor().toARGB32();
        _hex.text = ColorHex.format(_value);
        _hexError = null;
      });

  void _setColor(int argb) => setState(() {
        _value = 0xFF000000 | argb;
        _hsl = HSLColor.fromColor(Color(_value));
        _hex.text = ColorHex.format(_value);
        _hexError = null;
      });

  void _typed(String text) {
    final parsed = ColorHex.parse(text);
    setState(() {
      if (parsed == null) {
        _hexError = 'Type six hex digits, for example #1e1e2e';
        return;
      }
      _hexError = null;
      _value = parsed;
      _hsl = HSLColor.fromColor(Color(parsed));
    });
  }

  @override
  Widget build(BuildContext context) {
    final picks = <int>{for (final c in widget.suggestions) 0xFF000000 | c}.toList();
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BeforeAfter(before: widget.initial, after: _value),
            const SizedBox(height: 16),
            TextField(
              controller: _hex,
              onChanged: _typed,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(7),
              ],
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              decoration: InputDecoration(labelText: 'Hex colour', hintText: '#rrggbb', errorText: _hexError),
            ),
            const SizedBox(height: 8),
            _HslSlider(
              label: 'Hue',
              value: _hsl.hue,
              max: 360,
              shown: '${_hsl.hue.round()}°',
              onChanged: (v) => _setHsl(_hsl.withHue(v)),
            ),
            _HslSlider(
              label: 'Saturation',
              value: _hsl.saturation,
              max: 1,
              shown: '${(_hsl.saturation * 100).round()}%',
              onChanged: (v) => _setHsl(_hsl.withSaturation(v)),
            ),
            _HslSlider(
              label: 'Lightness',
              value: _hsl.lightness,
              max: 1,
              shown: '${(_hsl.lightness * 100).round()}%',
              onChanged: (v) => _setHsl(_hsl.withLightness(v)),
            ),
            if (picks.isNotEmpty) ...[
              const _Heading('From this theme'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final c in picks) _QuickPick(color: c, selected: c == _value, onTap: () => _setColor(c))],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (widget.clearLabel != null)
          TextButton(onPressed: () => Navigator.pop(context, const ColorPick(null)), child: Text(widget.clearLabel!)),
        FilledButton(onPressed: () => Navigator.pop(context, ColorPick(_value)), child: const Text('Use colour')),
      ],
    );
  }
}

/// A small muted heading inside the dialog.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColorsTheme.of(context).muted, fontWeight: FontWeight.w600),
        ),
      );
}

/// The colour before and after the change, side by side.
class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.before, required this.after});

  final int before;
  final int after;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      label: 'Colour ${ColorHex.format(after)}, was ${ColorHex.format(before)}',
      child: Container(
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.outline)),
        child: Row(
          children: [
            Expanded(child: ColoredBox(color: Color(0xFF000000 | before))),
            Expanded(flex: 2, child: ColoredBox(color: Color(after))),
          ],
        ),
      ),
    );
  }
}

/// One of the hue, saturation and lightness sliders, with its value.
class _HslSlider extends StatelessWidget {
  const _HslSlider({required this.label, required this.value, required this.max, required this.shown, required this.onChanged});

  final String label;
  final double value;
  final double max;
  final String shown;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = AppColorsTheme.of(context).muted;
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(value: value.clamp(0, max), max: max, onChanged: onChanged, semanticFormatterCallback: (_) => '$label $shown'),
        ),
        SizedBox(width: 44, child: Text(shown, textAlign: TextAlign.end, style: TextStyle(color: muted))),
      ],
    );
  }
}

/// A round swatch of one of the theme's colours.
class _QuickPick extends StatelessWidget {
  const _QuickPick({required this.color, required this.selected, required this.onTap});

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final hex = ColorHex.format(color);
    return Tooltip(
      message: hex,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Use $hex',
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: Border.all(color: selected ? colors.accent : colors.outline, width: selected ? 3 : 1),
            ),
          ),
        ),
      ),
    );
  }
}
