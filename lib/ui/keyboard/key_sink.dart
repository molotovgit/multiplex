import '../../sessions/terminal_controller.dart';
import '../../src/rust/api/terminal_types.dart';

/// Where the keyboard sends its input. The terminal in the app, a
/// recorder in tests, the live preview in settings.
abstract interface class KeySink {
  void sendText(String text, KeyModifiers mods);

  void sendKey(TerminalKey key, KeyModifiers mods);

  void pasteClipboard();
}

/// Sends keys to a [TerminalController].
///
/// The controller has its own sticky Ctrl and Alt (set by the key bar or
/// the hardware keyboard path). If one of them is on, it is added to the
/// next key and released, so both ways of setting Ctrl work together.
class ControllerKeySink implements KeySink {
  ControllerKeySink(this.controller);

  final TerminalController controller;

  @override
  void sendText(String text, KeyModifiers mods) => controller.textWith(text, _merge(mods));

  @override
  void sendKey(TerminalKey key, KeyModifiers mods) => controller.keyWith(key, _merge(mods));

  @override
  void pasteClipboard() => controller.pasteClipboard();

  KeyModifiers _merge(KeyModifiers mods) {
    final ctrl = controller.ctrlLatched, alt = controller.altLatched;
    if (ctrl) controller.toggleCtrl();
    if (alt) controller.toggleAlt();
    return KeyModifiers(ctrl: mods.ctrl || ctrl, alt: mods.alt || alt, shift: mods.shift);
  }
}
