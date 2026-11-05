import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// One option of a [StyleChoice].
class StyleOption<T> {
  const StyleOption(this.value, this.label);

  final T value;
  final String label;
}

/// A setting with a few named options, shown as chips that wrap onto more
/// lines at large text sizes. Each chip is a full 48 dp touch target.
class StyleChoice<T> extends StatelessWidget {
  const StyleChoice({super.key, required this.title, required this.options, required this.selected, required this.onChanged, this.description});

  final String title;
  final String? description;
  final List<StyleOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = AppColorsTheme.of(context).muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          if (description != null) Text(description!, style: text.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 4),
          Semantics(
            label: title,
            container: true,
            child: Wrap(
              spacing: 8,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: option.value == selected,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) => onChanged(option.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting with a range, such as the dimming of a picture.
class StyleSlider extends StatelessWidget {
  const StyleSlider({
    super.key,
    required this.title,
    required this.value,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double max;
  final int divisions;

  /// How the value reads, for example "40 %".
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: text.titleSmall)),
              Text(valueLabel, style: text.bodyMedium),
            ],
          ),
          Slider(
            value: value.clamp(0, max),
            max: max,
            divisions: divisions,
            label: valueLabel,
            semanticFormatterCallback: (_) => valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
