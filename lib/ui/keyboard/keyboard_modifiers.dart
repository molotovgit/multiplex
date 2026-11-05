import 'package:flutter/foundation.dart';

import '../../src/rust/api/terminal_types.dart';
import 'key_spec.dart';

/// The state of one modifier key.
enum ModifierMode {
  off,

  /// Applies to the next key only, then turns off.
  oneShot,

  /// Stays on until tapped again.
  locked,
}

/// Ctrl, Alt and Shift of the built-in keyboard.
///
/// Tap once: on for the next key. Tap twice quickly: locked. Tap a locked
/// or one-shot modifier again later: off.
class KeyboardModifiers extends ChangeNotifier {
  KeyboardModifiers({Duration Function()? clock}) : _clock = clock ?? MonotonicClock.now;

  /// Two taps closer together than this lock the modifier.
  static const doubleTapWindow = Duration(milliseconds: 350);

  final Duration Function() _clock;
  final _modes = {for (final m in ModifierKind.values) m: ModifierMode.off};
  final _lastTap = <ModifierKind, Duration>{};

  ModifierMode modeOf(ModifierKind key) => _modes[key]!;

  bool isOn(ModifierKind key) => _modes[key] != ModifierMode.off;

  void tap(ModifierKind key) {
    final now = _clock();
    final last = _lastTap[key];
    final quick = last != null && now - last <= doubleTapWindow;
    _modes[key] = switch (_modes[key]!) {
      ModifierMode.off => ModifierMode.oneShot,
      ModifierMode.oneShot => quick ? ModifierMode.locked : ModifierMode.off,
      ModifierMode.locked => ModifierMode.off,
    };
    _lastTap[key] = now;
    notifyListeners();
  }

  /// The modifiers for the key being sent. One-shot modifiers turn off.
  ActiveModifiers take() {
    final active = ActiveModifiers(ctrl: isOn(ModifierKind.ctrl), alt: isOn(ModifierKind.alt), shift: isOn(ModifierKind.shift));
    var changed = false;
    for (final key in ModifierKind.values) {
      if (_modes[key] == ModifierMode.oneShot) {
        _modes[key] = ModifierMode.off;
        changed = true;
      }
    }
    if (changed) notifyListeners();
    return active;
  }

  /// Turns everything off.
  void clear() {
    if (!_modes.values.any((m) => m != ModifierMode.off)) return;
    _modes.updateAll((_, _) => ModifierMode.off);
    notifyListeners();
  }
}

/// Which modifiers apply to one key press.
class ActiveModifiers {
  const ActiveModifiers({this.ctrl = false, this.alt = false, this.shift = false});

  static const none = ActiveModifiers();

  final bool ctrl;
  final bool alt;
  final bool shift;

  bool get any => ctrl || alt || shift;

  /// Shift is left out for text: it is already in the capital letter.
  KeyModifiers forText() => KeyModifiers(ctrl: ctrl, alt: alt, shift: false);

  KeyModifiers forKey() => KeyModifiers(ctrl: ctrl, alt: alt, shift: shift);

  /// "Ctrl+Alt+" for the preview echo.
  String get prefix => '${ctrl ? 'Ctrl+' : ''}${alt ? 'Alt+' : ''}';
}

/// Time that only moves forward, for double-tap detection.
abstract final class MonotonicClock {
  static final _watch = Stopwatch()..start();

  static Duration now() => _watch.elapsed;
}
