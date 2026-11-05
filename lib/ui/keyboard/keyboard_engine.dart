import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/terminal_types.dart';
import 'key_sink.dart';
import 'key_spec.dart';
import 'keyboard_modifiers.dart';
import 'keyboard_settings.dart';

/// The keyboard's logic, without widgets: which page is showing, the
/// modifiers, and turning key presses into terminal input.
class KeyboardEngine extends ChangeNotifier {
  KeyboardEngine({required this.sink, KeyboardModifiers? modifiers})
      : modifiers = modifiers ?? KeyboardModifiers(),
        _ownsModifiers = modifiers == null {
    this.modifiers.addListener(notifyListeners);
  }

  final KeySink sink;
  final KeyboardModifiers modifiers;
  final bool _ownsModifiers;

  /// Set by the panel on every build.
  KeyboardSettings settings = const KeyboardSettings();

  VoidCallback? onSnippets;
  VoidCallback? onHide;
  VoidCallback? onSwitchToSystem;

  /// Told what was sent, in words ("Ctrl+C", "Enter"). Used by the preview.
  ValueChanged<String>? onSent;

  KeyboardPage _page = KeyboardPage.letters;

  KeyboardPage get page => _page;

  bool get shiftOn => modifiers.isOn(ModifierKind.shift);

  void showPage(KeyboardPage page) {
    if (page == _page) return;
    _page = page;
    notifyListeners();
  }

  void press(KeySpec key) => perform(key.action);

  void perform(KeyAction action) {
    switch (action) {
      case TypeText(:final text):
        _type(text, isLetter: action.isLetter);
      case SendKey(:final key):
        _sendKey(key);
      case ToggleModifier(:final modifier):
        modifiers.tap(modifier);
      case ShowPage(:final page):
        showPage(page);
      case RunCommand(:final command):
        _run(command);
    }
  }

  /// A step of the space-bar trackpad.
  void moveCursor(TerminalKey arrow) => _sendKey(arrow);

  /// A tap of haptics and sound, as the user chose. Called on touch down
  /// so it matches the finger, not the release.
  void touchFeedback() {
    if (settings.haptics) HapticFeedback.selectionClick();
    if (settings.sound) SystemSound.play(SystemSoundType.click);
  }

  void _type(String text, {required bool isLetter}) {
    final mods = modifiers.take();
    var out = text;
    if (isLetter) {
      // Ctrl and Alt go with the plain letter; Shift alone makes a capital.
      out = mods.shift && !mods.ctrl ? text.toUpperCase() : text.toLowerCase();
    }
    sink.sendText(out, mods.forText());
    onSent?.call('${mods.prefix}${_describe(out, mods)}');
  }

  void _sendKey(TerminalKey key) {
    final mods = modifiers.take();
    sink.sendKey(key, mods.forKey());
    onSent?.call('${mods.prefix}${mods.shift ? 'Shift+' : ''}${KeyWords.of(key)}');
  }

  void _run(KeyCommand command) {
    switch (command) {
      case KeyCommand.paste:
        sink.pasteClipboard();
        onSent?.call('Paste');
      case KeyCommand.snippets:
        onSnippets?.call();
      case KeyCommand.hide:
        onHide?.call();
      case KeyCommand.systemKeyboard:
        onSwitchToSystem?.call();
    }
  }

  String _describe(String text, ActiveModifiers mods) {
    if (text == ' ') return 'Space';
    return mods.ctrl && text.length == 1 ? text.toUpperCase() : text;
  }

  @override
  void dispose() {
    modifiers.removeListener(notifyListeners);
    if (_ownsModifiers) modifiers.dispose();
    super.dispose();
  }
}

/// Short names of terminal keys, for the preview echo.
abstract final class KeyWords {
  static String of(TerminalKey key) => switch (key) {
        TerminalKey.enter => 'Enter',
        TerminalKey.tab => 'Tab',
        TerminalKey.backspace => 'Backspace',
        TerminalKey.escape => 'Esc',
        TerminalKey.up => 'Up',
        TerminalKey.down => 'Down',
        TerminalKey.left => 'Left',
        TerminalKey.right => 'Right',
        TerminalKey.home => 'Home',
        TerminalKey.end => 'End',
        TerminalKey.pageUp => 'Page up',
        TerminalKey.pageDown => 'Page down',
        TerminalKey.insert => 'Insert',
        TerminalKey.delete => 'Delete',
        _ => key.name.toUpperCase(),
      };
}
