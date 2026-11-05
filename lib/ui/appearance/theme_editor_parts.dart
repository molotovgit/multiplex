import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../common/widgets.dart';
import 'color_tools.dart';

/// A square of one theme colour, with a thin border so a colour close to
/// the screen's own background still shows.
class ColorSwatchBox extends StatelessWidget {
  const ColorSwatchBox({super.key, required this.color, this.size = 36});

  final int? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color == null ? null : Color(color!),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outline),
      ),
      child: color == null ? Icon(Icons.block, size: size * 0.5, color: colors.muted) : null,
    );
  }
}

/// One of the main colours (background, text, cursor, accent, selection):
/// a swatch, what the colour is used for, and its hex code.
class ColorRow extends StatelessWidget {
  const ColorRow({super.key, required this.label, required this.description, required this.color, required this.onTap, this.emptyText});

  final String label;
  final String description;

  /// Null for an optional colour that is not set.
  final int? color;
  final VoidCallback onTap;

  /// Shown instead of the hex code when [color] is null.
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final small = Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted);
    // The value sits under the description rather than at the end of the
    // row, so it can wrap when the user picks a large text size.
    return ListTile(
      leading: ColorSwatchBox(color: color),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(description),
          if (color == null) Text(emptyText ?? 'Not set', style: small) else MonoText(ColorHex.format(color!), style: small),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// The 16 terminal colours, normal and bright. Wide screens show two rows
/// of eight; phones show eight rows of two, one row per colour name.
class AnsiColorGrid extends StatelessWidget {
  const AnsiColorGrid({super.key, required this.ansi, required this.onTap});

  final List<int> ansi;

  /// Called with the palette index 0-15 of the tapped colour.
  final ValueChanged<int> onTap;

  /// Narrower than this, the grid turns on its side.
  static const _wideFrom = 560.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= _wideFrom ? _WideAnsiGrid(ansi: ansi, onTap: onTap) : _NarrowAnsiGrid(ansi: ansi, onTap: onTap),
      );
}

class _WideAnsiGrid extends StatelessWidget {
  const _WideAnsiGrid({required this.ansi, required this.onTap});

  final List<int> ansi;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColorsTheme.of(context).muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final bright in [false, true]) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
              child: Text(bright ? 'Bright' : 'Normal', style: label),
            ),
            Row(
              children: [
                for (var i = 0; i < 8; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _AnsiTile(index: bright ? i + 8 : i, color: ansi[bright ? i + 8 : i], onTap: onTap, showName: true),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NarrowAnsiGrid extends StatelessWidget {
  const _NarrowAnsiGrid({required this.ansi, required this.onTap});

  final List<int> ansi;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColorsTheme.of(context).muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 80),
              Expanded(child: Text('Normal', style: label)),
              const SizedBox(width: 8),
              Expanded(child: Text('Bright', style: label)),
            ],
          ),
          for (var i = 0; i < 8; i++)
            Padding(
              // 48 dp rows with 8 dp between them, so each colour is easy to hit.
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text(AnsiNames.normal[i])),
                  Expanded(child: _AnsiTile(index: i, color: ansi[i], onTap: onTap, showName: false)),
                  const SizedBox(width: 8),
                  Expanded(child: _AnsiTile(index: i + 8, color: ansi[i + 8], onTap: onTap, showName: false)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One terminal colour: a swatch and its hex code, and on wide screens
/// its name.
class _AnsiTile extends StatelessWidget {
  const _AnsiTile({required this.index, required this.color, required this.onTap, required this.showName});

  final int index;
  final int color;
  final ValueChanged<int> onTap;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final small = Theme.of(context).textTheme.bodySmall;
    final name = AnsiNames.of(index);
    final hex = ColorHex.format(color);
    final swatch = Container(
      height: showName ? 40 : 28,
      width: showName ? null : 28,
      decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(6), border: Border.all(color: colors.outline)),
    );
    final code = MonoText(hex, maxLines: 1, style: small?.copyWith(color: colors.muted));
    return Semantics(
      button: true,
      label: '$name, $hex',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTap(index),
        child: Container(
          // The swatch can be small, but the place to tap is at least 48 dp.
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.all(4),
          alignment: Alignment.centerLeft,
          child: showName
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    swatch,
                    const SizedBox(height: 4),
                    Text(AnsiNames.normal[index % 8], maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                    code,
                  ],
                )
              : Row(children: [swatch, const SizedBox(width: 8), Expanded(child: code)]),
        ),
      ),
    );
  }
}

/// Shown when the text colour barely stands out from the background.
class ContrastWarning extends StatelessWidget {
  const ContrastWarning({super.key, required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Text will be hard to read: the contrast with the background is ${ratio.toStringAsFixed(1)} to 1, '
                'and at least 4.5 to 1 is needed. Make the text or the background lighter or darker.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
