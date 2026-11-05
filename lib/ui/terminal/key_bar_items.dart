import 'package:flutter/material.dart';

import '../../src/rust/api/terminal_types.dart';

/// What a key in the bar above the keyboard does.
enum KeyBarAction {
  /// Sends a special key such as Esc or an arrow.
  key,

  /// Types a character that is awkward on phone keyboards.
  text,

  /// Sticky Ctrl: applies to the next key.
  ctrl,

  /// Sticky Alt: applies to the next key.
  alt,

  /// Pastes the clipboard.
  paste,

  /// Opens the snippet picker.
  snippets,
}

/// One possible key for the bar.
class KeyBarItem {
  const KeyBarItem({required this.id, required this.label, required this.action, this.key, this.text, this.icon, this.description});

  final String id;

  /// Short text on the key itself.
  final String label;
  final KeyBarAction action;
  final TerminalKey? key;
  final String? text;

  /// Shown instead of [label] when set.
  final IconData? icon;

  /// Longer name for the key bar editor.
  final String? description;

  String get name => description ?? label;
}

/// Every key the bar can hold. The user picks and orders them in
/// settings; [AppSettings.keyBar] stores the ids.
abstract final class KeyBarItems {
  static const all = [
    KeyBarItem(id: 'esc', label: 'Esc', action: KeyBarAction.key, key: TerminalKey.escape, description: 'Escape'),
    KeyBarItem(id: 'tab', label: 'Tab', action: KeyBarAction.key, key: TerminalKey.tab),
    KeyBarItem(id: 'ctrl', label: 'Ctrl', action: KeyBarAction.ctrl, description: 'Ctrl (sticky)'),
    KeyBarItem(id: 'alt', label: 'Alt', action: KeyBarAction.alt, description: 'Alt (sticky)'),
    KeyBarItem(id: 'left', label: '←', action: KeyBarAction.key, key: TerminalKey.left, icon: Icons.keyboard_arrow_left, description: 'Arrow left'),
    KeyBarItem(id: 'down', label: '↓', action: KeyBarAction.key, key: TerminalKey.down, icon: Icons.keyboard_arrow_down, description: 'Arrow down'),
    KeyBarItem(id: 'up', label: '↑', action: KeyBarAction.key, key: TerminalKey.up, icon: Icons.keyboard_arrow_up, description: 'Arrow up'),
    KeyBarItem(id: 'right', label: '→', action: KeyBarAction.key, key: TerminalKey.right, icon: Icons.keyboard_arrow_right, description: 'Arrow right'),
    KeyBarItem(id: 'pipe', label: '|', action: KeyBarAction.text, text: '|', description: 'Pipe |'),
    KeyBarItem(id: 'slash', label: '/', action: KeyBarAction.text, text: '/', description: 'Slash /'),
    KeyBarItem(id: 'backslash', label: r'\', action: KeyBarAction.text, text: r'\', description: r'Backslash \'),
    KeyBarItem(id: 'dash', label: '-', action: KeyBarAction.text, text: '-', description: 'Dash -'),
    KeyBarItem(id: 'underscore', label: '_', action: KeyBarAction.text, text: '_', description: 'Underscore _'),
    KeyBarItem(id: 'tilde', label: '~', action: KeyBarAction.text, text: '~', description: 'Tilde ~'),
    KeyBarItem(id: 'backtick', label: '`', action: KeyBarAction.text, text: '`', description: 'Backtick `'),
    KeyBarItem(id: 'dollar', label: r'$', action: KeyBarAction.text, text: r'$', description: r'Dollar $'),
    KeyBarItem(id: 'amp', label: '&', action: KeyBarAction.text, text: '&', description: 'Ampersand &'),
    KeyBarItem(id: 'star', label: '*', action: KeyBarAction.text, text: '*', description: 'Star *'),
    KeyBarItem(id: 'gt', label: '>', action: KeyBarAction.text, text: '>', description: 'Greater than >'),
    KeyBarItem(id: 'lt', label: '<', action: KeyBarAction.text, text: '<', description: 'Less than <'),
    KeyBarItem(id: 'colon', label: ':', action: KeyBarAction.text, text: ':', description: 'Colon :'),
    KeyBarItem(id: 'home', label: 'Home', action: KeyBarAction.key, key: TerminalKey.home),
    KeyBarItem(id: 'end', label: 'End', action: KeyBarAction.key, key: TerminalKey.end),
    KeyBarItem(id: 'pgup', label: 'PgUp', action: KeyBarAction.key, key: TerminalKey.pageUp, description: 'Page up'),
    KeyBarItem(id: 'pgdn', label: 'PgDn', action: KeyBarAction.key, key: TerminalKey.pageDown, description: 'Page down'),
    KeyBarItem(id: 'del', label: 'Del', action: KeyBarAction.key, key: TerminalKey.delete, description: 'Delete'),
    KeyBarItem(id: 'ins', label: 'Ins', action: KeyBarAction.key, key: TerminalKey.insert, description: 'Insert'),
    KeyBarItem(id: 'f1', label: 'F1', action: KeyBarAction.key, key: TerminalKey.f1),
    KeyBarItem(id: 'f2', label: 'F2', action: KeyBarAction.key, key: TerminalKey.f2),
    KeyBarItem(id: 'f3', label: 'F3', action: KeyBarAction.key, key: TerminalKey.f3),
    KeyBarItem(id: 'f4', label: 'F4', action: KeyBarAction.key, key: TerminalKey.f4),
    KeyBarItem(id: 'f5', label: 'F5', action: KeyBarAction.key, key: TerminalKey.f5),
    KeyBarItem(id: 'f6', label: 'F6', action: KeyBarAction.key, key: TerminalKey.f6),
    KeyBarItem(id: 'f7', label: 'F7', action: KeyBarAction.key, key: TerminalKey.f7),
    KeyBarItem(id: 'f8', label: 'F8', action: KeyBarAction.key, key: TerminalKey.f8),
    KeyBarItem(id: 'f9', label: 'F9', action: KeyBarAction.key, key: TerminalKey.f9),
    KeyBarItem(id: 'f10', label: 'F10', action: KeyBarAction.key, key: TerminalKey.f10),
    KeyBarItem(id: 'f11', label: 'F11', action: KeyBarAction.key, key: TerminalKey.f11),
    KeyBarItem(id: 'f12', label: 'F12', action: KeyBarAction.key, key: TerminalKey.f12),
    KeyBarItem(id: 'paste', label: 'Paste', action: KeyBarAction.paste, icon: Icons.content_paste, description: 'Paste clipboard'),
    KeyBarItem(id: 'snippets', label: 'Snippets', action: KeyBarAction.snippets, icon: Icons.bolt, description: 'Run a snippet'),
  ];

  static KeyBarItem? byId(String id) {
    for (final item in all) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// The items for a list of ids, skipping unknown ones.
  static List<KeyBarItem> resolve(List<String> ids) => [for (final id in ids) ?byId(id)];
}
