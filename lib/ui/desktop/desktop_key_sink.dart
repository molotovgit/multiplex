import '../../sessions/desktop_controller.dart';
import '../../src/rust/api/terminal_types.dart';
import '../keyboard/key_sink.dart';
import 'desktop_keys.dart';

/// Lets Multiplex's built-in keyboard type on the remote desktop: its keys
/// and the Ctrl, Alt and Shift it holds become Linux key presses. The
/// desktop's own sticky keys (Super and the rest on the key bar) are added
/// by the controller as usual.
class DesktopKeySink implements KeySink {
  DesktopKeySink(this.controller);

  final DesktopController controller;

  static const _keys = {
    TerminalKey.enter: LinuxKey.enter,
    TerminalKey.tab: LinuxKey.tab,
    TerminalKey.backspace: LinuxKey.backspace,
    TerminalKey.escape: LinuxKey.esc,
    TerminalKey.up: LinuxKey.up,
    TerminalKey.down: LinuxKey.down,
    TerminalKey.left: LinuxKey.left,
    TerminalKey.right: LinuxKey.right,
    TerminalKey.home: LinuxKey.home,
    TerminalKey.end: LinuxKey.end,
    TerminalKey.pageUp: LinuxKey.pageUp,
    TerminalKey.pageDown: LinuxKey.pageDown,
    TerminalKey.insert: LinuxKey.insert,
    TerminalKey.delete: LinuxKey.delete,
  };

  static int? codeFor(TerminalKey key) {
    final fixed = _keys[key];
    if (fixed != null) return fixed;
    final f = TerminalKey.values.indexOf(key) - TerminalKey.f1.index + 1;
    return f >= 1 && f <= 12 ? LinuxKey.function(f) : null;
  }

  static List<int> modsFor(KeyModifiers mods) => [if (mods.ctrl) LinuxKey.leftCtrl, if (mods.alt) LinuxKey.leftAlt, if (mods.shift) LinuxKey.leftShift];

  @override
  void sendText(String text, KeyModifiers mods) {
    final held = modsFor(mods);
    if (held.isEmpty) {
      controller.type(text);
      return;
    }
    // Ctrl+C and the like: the key itself, with the modifiers held.
    for (final rune in text.runes) {
      final stroke = UsLayout.stroke(String.fromCharCode(rune).toLowerCase()) ?? UsLayout.stroke(String.fromCharCode(rune));
      if (stroke == null) continue;
      controller.tap(stroke.code, extra: [...held, if (stroke.shift && !mods.shift) LinuxKey.leftShift]);
    }
  }

  @override
  void sendKey(TerminalKey key, KeyModifiers mods) {
    final code = codeFor(key);
    if (code != null) controller.tap(code, extra: modsFor(mods));
  }

  @override
  void pasteClipboard() => controller.pastePhoneClipboard();
}
