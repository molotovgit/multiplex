import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/ssh.dart';
import '../src/rust/api/touchpad.dart';
import '../ui/desktop/desktop_keys.dart';
import 'error_text.dart';
import 'key_target.dart';

/// The computer's virtual touchpad and keyboard, as the screen uses it.
/// The real one is in the Rust core; tests pass a stand-in.
abstract class TouchpadPipe {
  void moveBy(double dx, double dy);
  void scroll(double dx, double dy);
  void button(TouchpadButton button, bool down);
  void key(int code, bool down);
  void paste(String text);
  void releaseAll();

  /// Why it stopped (empty when closed from here).
  Stream<String> get ended;
  void close();
}

class RustTouchpadPipe implements TouchpadPipe {
  RustTouchpadPipe(this._pad);

  final RemoteTouchpad _pad;

  static Future<TouchpadPipe> open(SshSession ssh) async => RustTouchpadPipe(await ssh.openTouchpad());

  @override
  void moveBy(double dx, double dy) => _pad.moveBy(dx: dx, dy: dy);

  @override
  void scroll(double dx, double dy) => _pad.scroll(dx: dx, dy: dy);

  @override
  void button(TouchpadButton button, bool down) => _pad.button(button: button, down: down);

  @override
  void key(int code, bool down) => _pad.key(code: code, down: down);

  @override
  void paste(String text) => _pad.paste(text: text);

  @override
  void releaseAll() => _pad.releaseAll();

  @override
  Stream<String> get ended => _pad.ended();

  @override
  void close() => _pad.close();
}

/// Steering the computer with the phone as its touchpad and keyboard,
/// without the computer's picture.
class TouchpadController extends ChangeNotifier with StickyMods implements KeyTarget {
  TouchpadController(this._open);

  final Future<TouchpadPipe> Function() _open;
  TouchpadPipe? _pipe;
  StreamSubscription<String>? _ended;
  bool _starting = false;
  bool _disposed = false;

  /// Why the touchpad could not start or stopped, as a sentence.
  String? problem;

  bool get ready => _pipe != null;
  bool get starting => _starting;

  /// A button held by a hold-and-drag.
  bool dragging = false;

  /// Starts the computer's side. Safe to call again after a failure.
  Future<void> start() async {
    if (_starting || _pipe != null || _disposed) return;
    _starting = true;
    problem = null;
    notifyListeners();
    try {
      final pipe = await _open();
      if (_disposed) {
        pipe.close();
        return;
      }
      _pipe = pipe;
      _ended = pipe.ended.listen((reason) {
        if (_disposed) return;
        _pipe = null;
        dragging = false;
        problem = reason.isEmpty ? 'The touchpad was closed.' : reason;
        notifyListeners();
      });
    } catch (e) {
      problem = errorSentence(e, fallback: 'The computer did not answer.');
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Pointer.

  /// How far the pointer goes for a finger movement: slow is exact, fast
  /// crosses the screen.
  static Offset pointerStep(Offset finger) {
    final gain = 2.2 * (1.0 + math.min(finger.distance / 18.0, 1.6));
    return finger * gain;
  }

  void moveBy(Offset finger) {
    final step = pointerStep(finger);
    _pipe?.moveBy(step.dx, step.dy);
  }

  /// Two fingers: the page follows them.
  void scrollBy(Offset fingers) => _pipe?.scroll(-fingers.dx * 1.6, -fingers.dy * 1.6);

  /// A click with the sticky modifiers held (Super+click and the like).
  void click(TouchpadButton button) {
    final held = activeMods();
    for (final m in held) {
      _pipe?.key(m, true);
    }
    _pipe?.button(button, true);
    _pipe?.button(button, false);
    for (final m in held.reversed) {
      _pipe?.key(m, false);
    }
    consumeOnceMods();
  }

  void press(TouchpadButton button) {
    _pipe?.button(button, true);
    if (button == TouchpadButton.left) {
      dragging = true;
      notifyListeners();
    }
  }

  void release(TouchpadButton button) {
    _pipe?.button(button, false);
    if (button == TouchpadButton.left && dragging) {
      dragging = false;
      notifyListeners();
    }
  }

  // Keys.

  @override
  void tap(int code, {List<int> extra = const []}) {
    final held = [...activeMods(), ...extra.where((m) => !activeMods().contains(m))];
    for (final m in held) {
      _pipe?.key(m, true);
    }
    _pipe?.key(code, true);
    _pipe?.key(code, false);
    for (final m in held.reversed) {
      _pipe?.key(m, false);
    }
    consumeOnceMods();
  }

  @override
  void keyEvent(int code, bool pressed) => _pipe?.key(code, pressed);

  /// Types text. What the US layout cannot type (accents, other
  /// alphabets, emoji) is pasted through the computer's clipboard.
  @override
  void type(String text) {
    if (text.isEmpty) return;
    if (!UsLayout.canType(text)) {
      _pipe?.paste(text);
      return;
    }
    for (final rune in text.runes) {
      final stroke = UsLayout.stroke(String.fromCharCode(rune))!;
      tap(stroke.code, extra: stroke.shift ? const [LinuxKey.leftShift] : const []);
    }
  }

  @override
  Future<bool> pastePhoneClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return false;
    _pipe?.paste(text);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _ended?.cancel();
    _pipe?.releaseAll();
    _pipe?.close();
    super.dispose();
  }
}
