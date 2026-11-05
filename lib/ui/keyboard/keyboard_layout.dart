import 'package:flutter/material.dart';

import '../../src/rust/api/terminal_types.dart';
import 'key_spec.dart';
import 'keyboard_settings.dart';

/// The keys of every page for one letter arrangement. All pages have five
/// rows, so the keyboard keeps its height when the page changes.
class KeyboardLayout {
  KeyboardLayout._(this.kind) : _alternates = KeyAlternates(kind);

  /// Layouts are built once and reused.
  static final _cache = <KeyboardLayoutKind, KeyboardLayout>{};

  static KeyboardLayout of(KeyboardLayoutKind kind) => _cache.putIfAbsent(kind, () => KeyboardLayout._(kind));

  final KeyboardLayoutKind kind;
  final KeyAlternates _alternates;

  /// Rows of a page, top to bottom.
  List<List<KeySpec>> page(KeyboardPage page) => switch (page) {
        KeyboardPage.letters => _letters,
        KeyboardPage.symbols => _symbols,
        KeyboardPage.functions => _functions,
      };

  late final List<List<KeySpec>> _letters = [
    _digitRow,
    for (final (i, row) in _letterRows.indexed)
      [
        if (i == 2) KeySpec.modifier(ModifierKind.shift, width: 1.5),
        for (final c in row.split('')) _char(c),
        if (i == 2) KeyboardKeys.backspace(1.5),
      ],
    [
      KeySpec.page(KeyboardPage.symbols, '?123', 'Numbers and symbols', width: 1.5),
      KeyboardKeys.fnPage,
      _char('-'),
      KeyboardKeys.space(3),
      _char('/'),
      _char('.'),
      KeyboardKeys.enter(1.5),
    ],
  ];

  late final List<List<KeySpec>> _symbols = [
    _digitRow,
    [for (final c in r'-_=+/\|&;:'.split('')) _char(c)],
    [for (final c in r'(){}[]<>$`'.split('')) _char(c)],
    [for (final c in '\'"~^*?!#%'.split('')) _char(c), KeyboardKeys.backspace(1)],
    [
      KeySpec.page(KeyboardPage.letters, 'ABC', 'Letters', width: 1.5),
      KeyboardKeys.fnPage,
      _char('@'),
      KeyboardKeys.space(3),
      _char(','),
      _char('.'),
      KeyboardKeys.enter(1.5),
    ],
  ];

  /// Seven columns, with the arrows as an upside-down T on the right.
  late final List<List<KeySpec>> _functions = [
    [for (var i = 0; i < 6; i++) KeyboardKeys.fKey(i, 10 / 6)],
    [for (var i = 6; i < 12; i++) KeyboardKeys.fKey(i, 10 / 6)],
    [
      KeyboardKeys.special(TerminalKey.escape, 'Esc', 'Escape'),
      KeyboardKeys.special(TerminalKey.insert, 'Ins', 'Insert'),
      KeyboardKeys.special(TerminalKey.home, 'Home', 'Home'),
      KeyboardKeys.special(TerminalKey.pageUp, 'PgUp', 'Page up', repeats: true),
      KeySpec.modifier(ModifierKind.ctrl, width: 10 / 7),
      KeyboardKeys.arrow(TerminalKey.up),
      KeySpec.modifier(ModifierKind.alt, width: 10 / 7),
    ],
    [
      KeyboardKeys.special(TerminalKey.tab, 'Tab', 'Tab'),
      KeyboardKeys.special(TerminalKey.delete, 'Del', 'Delete', repeats: true),
      KeyboardKeys.special(TerminalKey.end, 'End', 'End'),
      KeyboardKeys.special(TerminalKey.pageDown, 'PgDn', 'Page down', repeats: true),
      KeyboardKeys.arrow(TerminalKey.left),
      KeyboardKeys.arrow(TerminalKey.down),
      KeyboardKeys.arrow(TerminalKey.right),
    ],
    [
      KeySpec.page(KeyboardPage.letters, 'ABC', 'Letters', width: 1.5),
      KeySpec.command(KeyCommand.paste, 'Paste', Icons.content_paste, 'Paste', width: 1.25),
      KeySpec.command(KeyCommand.snippets, 'Snippets', Icons.bolt, 'Snippets', width: 1.25),
      KeySpec.command(KeyCommand.history, 'History', Icons.history, 'Command history', width: 1.25),
      KeyboardKeys.space(1.5),
      KeyboardKeys.backspace(1.5),
      KeyboardKeys.enter(1.75),
    ],
  ];

  late final List<KeySpec> _digitRow = [for (final c in '1234567890'.split('')) _char(c)];

  List<String> get _letterRows => switch (kind) {
        KeyboardLayoutKind.qwerty => const ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'],
        KeyboardLayoutKind.qwertz => const ['qwertzuiop', 'asdfghjkl', 'yxcvbnm'],
        KeyboardLayoutKind.azerty => const ['azertyuiop', 'qsdfghjklm', 'wxcvbn'],
      };

  KeySpec _char(String c) => KeySpec.text(c, alternates: _alternates.of(c));
}

/// Keys that appear on several pages.
abstract final class KeyboardKeys {
  static final fnPage = KeySpec.page(KeyboardPage.functions, 'Fn', 'Function keys and navigation');

  static KeySpec backspace(double width) =>
      KeySpec.key(TerminalKey.backspace, 'Backspace', width: width, icon: Icons.backspace_outlined, spoken: 'Backspace', repeats: true);

  static KeySpec enter(double width) =>
      KeySpec.key(TerminalKey.enter, 'Enter', width: width, icon: Icons.keyboard_return, spoken: 'Enter');

  static KeySpec space(double width) => KeySpec(
        label: 'Space',
        action: const TypeText(' '),
        width: width,
        spoken: 'Space, drag to move the cursor',
        repeats: true,
        trackpad: true,
      );

  static KeySpec special(TerminalKey key, String label, String spoken, {bool repeats = false}) =>
      KeySpec.key(key, label, width: 10 / 7, spoken: spoken, repeats: repeats);

  static KeySpec fKey(int index, double width) => KeySpec.key(fKeys[index], 'F${index + 1}', width: width);

  static KeySpec arrow(TerminalKey key) => KeySpec.key(key, _arrowNames[key]!, width: 10 / 7, icon: _arrowIcons[key], spoken: _arrowNames[key], repeats: true);

  static const fKeys = [
    TerminalKey.f1,
    TerminalKey.f2,
    TerminalKey.f3,
    TerminalKey.f4,
    TerminalKey.f5,
    TerminalKey.f6,
    TerminalKey.f7,
    TerminalKey.f8,
    TerminalKey.f9,
    TerminalKey.f10,
    TerminalKey.f11,
    TerminalKey.f12,
  ];

  static const _arrowNames = {
    TerminalKey.up: 'Arrow up',
    TerminalKey.down: 'Arrow down',
    TerminalKey.left: 'Arrow left',
    TerminalKey.right: 'Arrow right',
  };

  static const _arrowIcons = {
    TerminalKey.up: Icons.keyboard_arrow_up,
    TerminalKey.down: Icons.keyboard_arrow_down,
    TerminalKey.left: Icons.keyboard_arrow_left,
    TerminalKey.right: Icons.keyboard_arrow_right,
  };
}

/// The characters offered on long press (and by a swipe up, the first
/// one). Letters give the shell symbols, digits give their shifted symbol
/// and an F-key, and the European layouts add their accented letters.
class KeyAlternates {
  const KeyAlternates(this.kind);

  final KeyboardLayoutKind kind;

  static const _letters = {
    'q': '`', 'w': '~', 'e': '|', 'r': '{', 't': '}', 'y': '[', 'u': ']', 'i': '<', 'o': '>', 'p': r'\', //
    'a': '@', 's': '#', 'd': r'$', 'f': '%', 'g': '^', 'h': '&', 'j': '*', 'k': '(', 'l': ')', 'm': '=',
    'z': ';', 'x': ':', 'c': "'", 'v': '"', 'b': '?', 'n': '!',
  };

  static const _digits = '!@#\$%^&*()';

  static const _symbols = {
    '-': ['_', '~'],
    '/': [r'\', '|'],
    '.': [',', ':', ';'],
    ',': [';'],
    '(': ['[', '{', '<'],
    ')': [']', '}', '>'],
    "'": ['"', '`'],
    '=': ['+'],
    '&': ['|'],
    '*': ['#'],
  };

  static const _accents = {
    KeyboardLayoutKind.qwertz: {'a': 'ä', 'o': 'ö', 'u': 'ü', 's': 'ß'},
    KeyboardLayoutKind.azerty: {'e': 'éèêë', 'a': 'àâ', 'c': 'ç', 'u': 'ùû', 'i': 'îï', 'o': 'ô'},
  };

  List<KeySpec> of(String c) {
    final digit = '1234567890'.indexOf(c);
    if (digit >= 0) {
      return [KeySpec.text(_digits[digit]), KeyboardKeys.fKey(digit, 1)];
    }
    final symbol = _letters[c];
    if (symbol != null) {
      final accents = _accents[kind]?[c] ?? '';
      return [KeySpec.text(symbol), for (final a in accents.split('')) if (a.isNotEmpty) KeySpec.text(a)];
    }
    return [for (final s in _symbols[c] ?? const <String>[]) KeySpec.text(s)];
  }
}
