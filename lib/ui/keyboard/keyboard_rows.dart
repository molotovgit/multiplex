import 'package:flutter/material.dart';

import '../terminal/key_bar_items.dart';
import 'key_cap.dart';
import 'key_face.dart';
import 'key_spec.dart';
import 'keyboard_engine.dart';
import 'keyboard_style.dart';

/// A row of keys sharing the width by their units. Rows shorter than ten
/// units are centred.
class KeyRow extends StatelessWidget {
  const KeyRow({super.key, required this.keys, required this.engine, required this.look});

  final List<KeySpec> keys;
  final KeyboardEngine engine;
  final KeyLook look;

  /// A full row is this many key units wide.
  static const units = 10.0;

  /// Units become flex values with this precision.
  static const _scale = 120;

  @override
  Widget build(BuildContext context) {
    final used = keys.fold<double>(0, (sum, k) => sum + k.width);
    final side = ((units - used) / 2 * _scale).round();
    return SizedBox(
      height: look.metrics.rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (side > 0) Spacer(flex: side),
          for (final key in keys)
            Expanded(
              flex: (key.width * _scale).round(),
              child: KeyCap(spec: key, engine: engine, look: look),
            ),
          if (side > 0) Spacer(flex: side),
        ],
      ),
    );
  }
}

/// The terminal row on top: the user's key bar keys in their order
/// (scrolling sideways when they do not fit), then the fixed "system
/// keyboard" and "hide" keys.
class TerminalTopRow extends StatelessWidget {
  const TerminalTopRow({super.key, required this.keyBarIds, required this.engine, required this.look});

  final List<String> keyBarIds;
  final KeyboardEngine engine;
  final KeyLook look;

  static final _system = KeySpec.command(KeyCommand.systemKeyboard, 'Keyboard', Icons.language, 'Use the system keyboard');
  static final _hide = KeySpec.command(KeyCommand.hide, 'Hide', Icons.keyboard_hide_outlined, 'Hide the keyboard');

  /// Ctrl and Alt must be reachable next to the letters, so they are
  /// added at the front when the user's bar leaves them out.
  static List<KeySpec> keysFor(List<String> ids) {
    final items = KeyBarItems.resolve(ids);
    final missing = [
      for (final id in const ['ctrl', 'alt'])
        if (!ids.contains(id)) KeyBarItems.byId(id)!,
    ];
    return [for (final item in [...missing, ...items]) KeySpec.fromBarItem(item)];
  }

  static double widthOf(KeySpec key) =>
      key.icon != null || key.label.length <= 2 ? KeyboardMetrics.topKeyWidth : KeyboardMetrics.topKeyWideWidth;

  @override
  Widget build(BuildContext context) {
    final keys = keysFor(keyBarIds);
    return SizedBox(
      height: look.metrics.rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final key in keys)
                  SizedBox(
                    width: widthOf(key),
                    child: KeyCap(spec: key, engine: engine, look: look, inScrollingRow: true),
                  ),
              ],
            ),
          ),
          for (final key in [_system, _hide])
            SizedBox(
              width: KeyboardMetrics.topKeyWidth,
              child: KeyCap(spec: key, engine: engine, look: look),
            ),
        ],
      ),
    );
  }
}
