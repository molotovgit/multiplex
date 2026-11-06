import 'package:flutter/material.dart';

import '../../app/theme_style.dart';

import 'key_spec.dart';
import 'keyboard_modifiers.dart';
import 'keyboard_style.dart';

/// Everything a key needs to draw itself.
class KeyLook {
  const KeyLook({required this.palette, required this.metrics, required this.text, required this.showHints});

  final KeyboardPalette palette;
  final KeyboardMetrics metrics;
  final KeyTextStyles text;

  /// Show the alternate small in the corner.
  final bool showHints;

  BorderRadius get radius => BorderRadius.circular(metrics.radius);
}

/// How one key looks: its cap, label, corner hint and modifier state.
/// Drawing only; [KeyCap] handles the touches.
class KeyFace extends StatelessWidget {
  const KeyFace({super.key, required this.spec, required this.look, required this.pressed, required this.shift, this.mode});

  final KeySpec spec;
  final KeyLook look;
  final bool pressed;

  /// Shift is on: letters show as capitals.
  final bool shift;

  /// Set for modifier keys.
  final ModifierMode? mode;

  /// How far the hint sits from the corner: further in on rounder keys,
  /// so it stays inside the curve instead of on it.
  double get _hintInset => (look.metrics.radius * 0.3).clamp(3.0, 8.0);

  double get _hintClearance => _hintInset + 2;

  @override
  Widget build(BuildContext context) {
    final p = look.palette;
    final locked = mode == ModifierMode.locked;
    final oneShot = mode == ModifierMode.oneShot;
    var fill = p.fill(spec);
    if (oneShot) fill = Color.alphaBlend(p.accentSoft, fill);
    if (locked) fill = p.accent;
    if (pressed) fill = Color.alphaBlend(p.pressed.withValues(alpha: 0.6), fill);
    final fg = locked ? p.onAccent : p.label;
    final hint = look.showHints && spec.alternates.isNotEmpty ? spec.alternates.first.label : null;
    final cap = look.metrics.cap;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: look.metrics.gapX, vertical: look.metrics.gapY),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: look.radius,
          border: oneShot
              ? Border.all(color: p.accent, width: 1.5)
              : (cap == KeyCapStyle.outlined ? Border.all(color: p.bubbleBorder) : null),
          boxShadow: cap == KeyCapStyle.raised ? [BoxShadow(color: p.shadow, offset: const Offset(0, 1))] : null,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // On a key narrower than its rounding (a pill) there is no
            // corner to put the hint in, so it sits centred on top.
            final pill = look.metrics.radius * 2 >= box.maxWidth - 1;
            final hintShown = hint != null && hint.length <= 3;
            final hintHeight = (look.text.hint?.fontSize ?? 10) * 1.2;
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Padding(
                    // The label sits a little lower to keep clear of the hint.
                    padding: EdgeInsets.only(left: 2, right: 2, top: !hintShown ? 0 : (pill ? hintHeight : _hintClearance)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _KeyLabel(spec: spec, look: look, color: fg, shift: shift, mode: mode),
                    ),
                  ),
                ),
                if (hintShown)
                  pill
                      ? Positioned(top: 3, left: 0, right: 0, child: Text(hint, style: look.text.hint, textAlign: TextAlign.center))
                      : Positioned(top: _hintInset, right: _hintInset + 1, child: Text(hint, style: look.text.hint)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The middle of a key: an icon, a character or a word, plus the state
/// marks of a modifier (a lock icon when locked, a bar when one-shot), so
/// the state never depends on colour alone.
class _KeyLabel extends StatelessWidget {
  const _KeyLabel({required this.spec, required this.look, required this.color, required this.shift, required this.mode});

  final KeySpec spec;
  final KeyLook look;
  final Color color;
  final bool shift;
  final ModifierMode? mode;

  static const _iconSize = 20.0;
  static const _markSize = 12.0;

  @override
  Widget build(BuildContext context) {
    final label = spec.labelFor(shift: shift);
    final isShift = spec.action is ToggleModifier && (spec.action as ToggleModifier).modifier == ModifierKind.shift;
    final Widget main;
    if (isShift && mode == ModifierMode.locked) {
      main = Icon(Icons.keyboard_capslock, size: _iconSize, color: color);
    } else if (spec.icon != null) {
      main = Icon(spec.icon, size: _iconSize, color: color);
    } else {
      final style = label.length == 1 ? look.text.character : look.text.word;
      main = Text(label, style: style?.copyWith(color: color), maxLines: 1);
    }
    if (mode == ModifierMode.locked && !isShift) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: _markSize, color: color),
          const SizedBox(width: 4),
          main,
        ],
      );
    }
    if (mode == ModifierMode.oneShot) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          main,
          const SizedBox(height: 4),
          Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(color: look.palette.accent, borderRadius: BorderRadius.circular(2)),
          ),
        ],
      );
    }
    return main;
  }
}

/// The bubble above the finger showing the character being typed.
class KeyPreviewBubble extends StatelessWidget {
  const KeyPreviewBubble({super.key, required this.label, required this.look, required this.size});

  final String label;
  final KeyLook look;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final p = look.palette;
    final style = Theme.of(context).textTheme.headlineSmall?.copyWith(color: p.label, fontWeight: look.text.character?.fontWeight);
    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.bubble,
        borderRadius: look.radius,
        border: Border.all(color: p.bubbleBorder),
        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: style, maxLines: 1)),
    );
  }
}

/// The row of alternates shown on long press. The one under the finger
/// is filled with the accent and slightly larger.
class KeyAlternatesPopup extends StatelessWidget {
  const KeyAlternatesPopup({super.key, required this.keys, required this.choice, required this.cell, required this.height, required this.look});

  final List<KeySpec> keys;
  final int choice;
  final double cell;
  final double height;
  final KeyLook look;

  static const _padding = 2.0;

  @override
  Widget build(BuildContext context) {
    final p = look.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: p.bubble,
        borderRadius: look.radius,
        border: Border.all(color: p.bubbleBorder),
        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, key) in keys.indexed)
            Container(
              // The popup is exactly cell * count wide; the padding comes out of the cells.
              width: (cell * keys.length - _padding * 2) / keys.length,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: i == choice ? p.accent : null, borderRadius: look.radius),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  key.label,
                  maxLines: 1,
                  style: (key.label.length == 1 ? text.titleLarge : text.labelLarge)?.copyWith(
                    color: i == choice ? p.onAccent : p.label,
                    fontWeight: look.text.character?.fontWeight,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
