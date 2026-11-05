import 'package:flutter/material.dart';

import '../../src/rust/api/terminal_types.dart';
import '../terminal/key_bar_items.dart';

/// The keyboard's pages.
enum KeyboardPage { letters, symbols, functions }

/// Keys that change the next key instead of typing.
enum ModifierKind {
  ctrl('Ctrl', 'Control'),
  alt('Alt', 'Alt'),
  shift('Shift', 'Shift');

  const ModifierKind(this.label, this.spokenName);

  /// Short text on the key.
  final String label;

  /// What a screen reader says.
  final String spokenName;
}

/// Keys that do something other than send input.
enum KeyCommand { paste, snippets, hide, systemKeyboard }

/// How strongly a key stands out: plain typing keys or the darker
/// "special" keys around them.
enum KeyTone { normal, special }

/// What happens when a key is pressed.
sealed class KeyAction {
  const KeyAction();
}

/// Types text. Single letters follow Shift.
final class TypeText extends KeyAction {
  const TypeText(this.text);

  final String text;

  bool get isLetter => text.length == 1 && text.toUpperCase() != text.toLowerCase();
}

/// Sends a terminal key such as Enter, an arrow or F5.
final class SendKey extends KeyAction {
  const SendKey(this.key);

  final TerminalKey key;
}

/// Turns Ctrl, Alt or Shift on or off.
final class ToggleModifier extends KeyAction {
  const ToggleModifier(this.modifier);

  final ModifierKind modifier;
}

/// Switches to another page of the keyboard.
final class ShowPage extends KeyAction {
  const ShowPage(this.page);

  final KeyboardPage page;
}

/// Paste, snippets, hide the keyboard, or switch to the system keyboard.
final class RunCommand extends KeyAction {
  const RunCommand(this.command);

  final KeyCommand command;
}

/// One key: what it shows, what it does and how it behaves.
class KeySpec {
  const KeySpec({
    required this.label,
    required this.action,
    this.width = 1,
    this.icon,
    this.spoken,
    this.alternates = const [],
    this.repeats = false,
    this.trackpad = false,
    this.tone = KeyTone.normal,
  });

  /// A key that types [text]; [alternates] are offered on long press.
  factory KeySpec.text(String text, {double width = 1, List<KeySpec> alternates = const [], String? spoken}) =>
      KeySpec(label: text, action: TypeText(text), width: width, alternates: alternates, spoken: spoken ?? KeyNames.spokenFor(text));

  /// A terminal key such as F1 or Home.
  factory KeySpec.key(TerminalKey key, String label, {double width = 1, IconData? icon, String? spoken, bool repeats = false}) => KeySpec(
        label: label,
        action: SendKey(key),
        width: width,
        icon: icon,
        spoken: spoken,
        repeats: repeats,
        tone: KeyTone.special,
      );

  factory KeySpec.modifier(ModifierKind modifier, {double width = 1}) => KeySpec(
        label: modifier.label,
        action: ToggleModifier(modifier),
        width: width,
        icon: modifier == ModifierKind.shift ? Icons.arrow_upward : null,
        spoken: modifier.spokenName,
        tone: KeyTone.special,
      );

  factory KeySpec.page(KeyboardPage page, String label, String spoken, {double width = 1}) =>
      KeySpec(label: label, action: ShowPage(page), width: width, spoken: spoken, tone: KeyTone.special);

  factory KeySpec.command(KeyCommand command, String label, IconData icon, String spoken, {double width = 1}) =>
      KeySpec(label: label, action: RunCommand(command), width: width, icon: icon, spoken: spoken, tone: KeyTone.special);

  /// A key from the user's key bar (the top row reuses those keys).
  factory KeySpec.fromBarItem(KeyBarItem item) {
    switch (item.action) {
      case KeyBarAction.key:
        return KeySpec.key(item.key!, item.label, icon: item.icon, spoken: item.name, repeats: KeyNames.repeating.contains(item.key));
      case KeyBarAction.text:
        return KeySpec(label: item.label, action: TypeText(item.text!), spoken: item.name, tone: KeyTone.special);
      case KeyBarAction.ctrl:
        return KeySpec.modifier(ModifierKind.ctrl);
      case KeyBarAction.alt:
        return KeySpec.modifier(ModifierKind.alt);
      case KeyBarAction.paste:
        return KeySpec.command(KeyCommand.paste, item.label, item.icon ?? Icons.content_paste, 'Paste');
      case KeyBarAction.snippets:
        return KeySpec.command(KeyCommand.snippets, item.label, item.icon ?? Icons.bolt, 'Snippets');
    }
  }

  /// Text on the key (letters are shown in capitals while Shift is on).
  final String label;
  final KeyAction action;

  /// Width in key units; a row is ten units wide.
  final double width;

  /// Shown instead of [label] when set.
  final IconData? icon;

  /// What a screen reader says; [label] when not set.
  final String? spoken;

  /// Offered in a popup on long press. The first one is also typed by a
  /// swipe up and shown in the corner of the key.
  final List<KeySpec> alternates;

  /// Holding the key repeats it.
  final bool repeats;

  /// Dragging on the key moves the cursor (the space bar).
  final bool trackpad;
  final KeyTone tone;

  bool get isLetter => action is TypeText && (action as TypeText).isLetter;

  /// Keys that show a bubble above the finger: characters, not space.
  bool get previews => action is TypeText && !trackpad;

  String labelFor({required bool shift}) => shift && isLetter ? label.toUpperCase() : label;

  String spokenFor({required bool shift}) => spoken ?? labelFor(shift: shift);
}

/// Names and groups of keys used in several places.
abstract final class KeyNames {
  /// Keys that repeat while held when they come from the key bar.
  static const repeating = {
    TerminalKey.up,
    TerminalKey.down,
    TerminalKey.left,
    TerminalKey.right,
    TerminalKey.backspace,
    TerminalKey.delete,
    TerminalKey.pageUp,
    TerminalKey.pageDown,
  };

  static const _spoken = {
    ' ': 'Space',
    '|': 'Pipe',
    '&': 'Ampersand',
    ';': 'Semicolon',
    '<': 'Less than',
    '>': 'Greater than',
    '(': 'Left parenthesis',
    ')': 'Right parenthesis',
    '{': 'Left brace',
    '}': 'Right brace',
    '[': 'Left bracket',
    ']': 'Right bracket',
    r'$': 'Dollar',
    '`': 'Backtick',
    "'": 'Single quote',
    '"': 'Double quote',
    r'\': 'Backslash',
    '~': 'Tilde',
    '^': 'Caret',
    '*': 'Star',
    '?': 'Question mark',
    '!': 'Exclamation mark',
    '#': 'Hash',
    '%': 'Percent',
    '=': 'Equals',
    '+': 'Plus',
    '-': 'Dash',
    '_': 'Underscore',
    '/': 'Slash',
    ':': 'Colon',
    '@': 'At sign',
    ',': 'Comma',
    '.': 'Dot',
  };

  /// A screen reader name for a symbol; null for letters and digits.
  static String? spokenFor(String text) => _spoken[text];
}
