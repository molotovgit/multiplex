import 'package:flutter/services.dart';

/// Linux input key codes (`linux/input-event-codes.h`), which the remote
/// desktop expects, and the US layout it types them with.
abstract final class LinuxKey {
  static const esc = 1;
  static const backspace = 14;
  static const tab = 15;
  static const enter = 28;
  static const leftCtrl = 29;
  static const leftShift = 42;
  static const leftAlt = 56;
  static const space = 57;
  static const capsLock = 58;
  static const f1 = 59;
  static const f11 = 87;
  static const f12 = 88;
  static const rightCtrl = 97;
  static const print = 99;
  static const rightAlt = 100;
  static const home = 102;
  static const up = 103;
  static const pageUp = 104;
  static const left = 105;
  static const right = 106;
  static const end = 107;
  static const down = 108;
  static const pageDown = 109;
  static const insert = 110;
  static const delete = 111;
  static const mute = 113;
  static const volumeDown = 114;
  static const volumeUp = 115;
  static const leftMeta = 125;
  static const rightMeta = 126;
  static const v = 47;

  /// F1 to F12.
  static int function(int n) => n <= 10 ? f1 + n - 1 : (n == 11 ? f11 : f12);

  /// Keys that change others and are held, not typed.
  static const modifiers = {leftCtrl, leftShift, leftAlt, leftMeta, rightCtrl, rightAlt, rightMeta};
}

/// One character as key presses: the key and whether Shift is held.
class KeyStroke {
  const KeyStroke(this.code, {this.shift = false});

  final int code;
  final bool shift;
}

/// Turns text into key strokes on a US layout.
abstract final class UsLayout {
  static const _row1 = '1234567890-='; // codes 2..13
  static const _row1Shift = '!@#\$%^&*()_+';
  static const _letters = {
    'q': 16, 'w': 17, 'e': 18, 'r': 19, 't': 20, 'y': 21, 'u': 22, 'i': 23, 'o': 24, 'p': 25, //
    'a': 30, 's': 31, 'd': 32, 'f': 33, 'g': 34, 'h': 35, 'j': 36, 'k': 37, 'l': 38, //
    'z': 44, 'x': 45, 'c': 46, 'v': 47, 'b': 48, 'n': 49, 'm': 50,
  };
  static const _symbols = {
    '[': KeyStroke(26), '{': KeyStroke(26, shift: true), //
    ']': KeyStroke(27), '}': KeyStroke(27, shift: true),
    ';': KeyStroke(39), ':': KeyStroke(39, shift: true),
    "'": KeyStroke(40), '"': KeyStroke(40, shift: true),
    '`': KeyStroke(41), '~': KeyStroke(41, shift: true),
    '\\': KeyStroke(43), '|': KeyStroke(43, shift: true),
    ',': KeyStroke(51), '<': KeyStroke(51, shift: true),
    '.': KeyStroke(52), '>': KeyStroke(52, shift: true),
    '/': KeyStroke(53), '?': KeyStroke(53, shift: true),
    ' ': KeyStroke(LinuxKey.space),
    '\n': KeyStroke(LinuxKey.enter),
    '\t': KeyStroke(LinuxKey.tab),
  };

  /// The stroke for [char], or null when the US layout cannot type it
  /// (accents, Cyrillic, emoji: those go through the clipboard instead).
  static KeyStroke? stroke(String char) {
    final letter = _letters[char];
    if (letter != null) return KeyStroke(letter);
    final upper = _letters[char.toLowerCase()];
    if (upper != null && char != char.toLowerCase()) return KeyStroke(upper, shift: true);
    var i = _row1.indexOf(char);
    if (i >= 0) return KeyStroke(2 + i);
    i = _row1Shift.indexOf(char);
    if (i >= 0) return KeyStroke(2 + i, shift: true);
    return _symbols[char];
  }

  /// True when every character of [text] can be typed as keys.
  static bool canType(String text) => text.runes.every((r) => stroke(String.fromCharCode(r)) != null);
}

/// Physical keys of a hardware keyboard (Bluetooth, USB) to Linux codes.
abstract final class HardwareKeys {
  static int? code(PhysicalKeyboardKey key) => _map[key];

  static final Map<PhysicalKeyboardKey, int> _map = {
    PhysicalKeyboardKey.escape: LinuxKey.esc,
    PhysicalKeyboardKey.digit1: 2, PhysicalKeyboardKey.digit2: 3, PhysicalKeyboardKey.digit3: 4, //
    PhysicalKeyboardKey.digit4: 5, PhysicalKeyboardKey.digit5: 6, PhysicalKeyboardKey.digit6: 7,
    PhysicalKeyboardKey.digit7: 8, PhysicalKeyboardKey.digit8: 9, PhysicalKeyboardKey.digit9: 10,
    PhysicalKeyboardKey.digit0: 11, PhysicalKeyboardKey.minus: 12, PhysicalKeyboardKey.equal: 13,
    PhysicalKeyboardKey.backspace: LinuxKey.backspace, PhysicalKeyboardKey.tab: LinuxKey.tab,
    PhysicalKeyboardKey.keyQ: 16, PhysicalKeyboardKey.keyW: 17, PhysicalKeyboardKey.keyE: 18,
    PhysicalKeyboardKey.keyR: 19, PhysicalKeyboardKey.keyT: 20, PhysicalKeyboardKey.keyY: 21,
    PhysicalKeyboardKey.keyU: 22, PhysicalKeyboardKey.keyI: 23, PhysicalKeyboardKey.keyO: 24,
    PhysicalKeyboardKey.keyP: 25, PhysicalKeyboardKey.bracketLeft: 26, PhysicalKeyboardKey.bracketRight: 27,
    PhysicalKeyboardKey.enter: LinuxKey.enter, PhysicalKeyboardKey.controlLeft: LinuxKey.leftCtrl,
    PhysicalKeyboardKey.keyA: 30, PhysicalKeyboardKey.keyS: 31, PhysicalKeyboardKey.keyD: 32,
    PhysicalKeyboardKey.keyF: 33, PhysicalKeyboardKey.keyG: 34, PhysicalKeyboardKey.keyH: 35,
    PhysicalKeyboardKey.keyJ: 36, PhysicalKeyboardKey.keyK: 37, PhysicalKeyboardKey.keyL: 38,
    PhysicalKeyboardKey.semicolon: 39, PhysicalKeyboardKey.quote: 40, PhysicalKeyboardKey.backquote: 41,
    PhysicalKeyboardKey.shiftLeft: LinuxKey.leftShift, PhysicalKeyboardKey.backslash: 43,
    PhysicalKeyboardKey.keyZ: 44, PhysicalKeyboardKey.keyX: 45, PhysicalKeyboardKey.keyC: 46,
    PhysicalKeyboardKey.keyV: 47, PhysicalKeyboardKey.keyB: 48, PhysicalKeyboardKey.keyN: 49,
    PhysicalKeyboardKey.keyM: 50, PhysicalKeyboardKey.comma: 51, PhysicalKeyboardKey.period: 52,
    PhysicalKeyboardKey.slash: 53, PhysicalKeyboardKey.shiftRight: 54, PhysicalKeyboardKey.altLeft: LinuxKey.leftAlt,
    PhysicalKeyboardKey.space: LinuxKey.space, PhysicalKeyboardKey.capsLock: LinuxKey.capsLock,
    PhysicalKeyboardKey.f1: 59, PhysicalKeyboardKey.f2: 60, PhysicalKeyboardKey.f3: 61, PhysicalKeyboardKey.f4: 62,
    PhysicalKeyboardKey.f5: 63, PhysicalKeyboardKey.f6: 64, PhysicalKeyboardKey.f7: 65, PhysicalKeyboardKey.f8: 66,
    PhysicalKeyboardKey.f9: 67, PhysicalKeyboardKey.f10: 68, PhysicalKeyboardKey.f11: 87, PhysicalKeyboardKey.f12: 88,
    PhysicalKeyboardKey.controlRight: LinuxKey.rightCtrl, PhysicalKeyboardKey.printScreen: LinuxKey.print,
    PhysicalKeyboardKey.altRight: LinuxKey.rightAlt, PhysicalKeyboardKey.home: LinuxKey.home,
    PhysicalKeyboardKey.arrowUp: LinuxKey.up, PhysicalKeyboardKey.pageUp: LinuxKey.pageUp,
    PhysicalKeyboardKey.arrowLeft: LinuxKey.left, PhysicalKeyboardKey.arrowRight: LinuxKey.right,
    PhysicalKeyboardKey.end: LinuxKey.end, PhysicalKeyboardKey.arrowDown: LinuxKey.down,
    PhysicalKeyboardKey.pageDown: LinuxKey.pageDown, PhysicalKeyboardKey.insert: LinuxKey.insert,
    PhysicalKeyboardKey.delete: LinuxKey.delete, PhysicalKeyboardKey.metaLeft: LinuxKey.leftMeta,
    PhysicalKeyboardKey.metaRight: LinuxKey.rightMeta,
  };
}
