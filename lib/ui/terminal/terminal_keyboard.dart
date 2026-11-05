import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sessions/terminal_controller.dart';
import '../../src/rust/api/terminal_types.dart';

/// Receives typing for the terminal.
///
/// Phone keyboards only talk to text fields, so a hidden text field holds
/// the focus. It always contains a few invisible placeholder characters:
/// when one disappears the user pressed Backspace, when text is added the
/// user typed. Everything is forwarded to the shell and the field is reset.
///
/// Hardware keys that are not text (arrows, Ctrl+C, F-keys) are caught
/// before the text field sees them.
class TerminalKeyboard extends StatefulWidget {
  const TerminalKeyboard({super.key, required this.controller, required this.focusNode, required this.child, this.systemKeyboard = true});

  final TerminalController controller;
  final FocusNode focusNode;
  final Widget child;

  /// False while the built-in keyboard is in use: the field keeps focus
  /// (hardware keys still work) but the phone's keyboard stays closed.
  final bool systemKeyboard;

  @override
  State<TerminalKeyboard> createState() => _TerminalKeyboardState();
}

class _TerminalKeyboardState extends State<TerminalKeyboard> {
  /// Zero-width spaces: invisible, and phone keyboards can delete them.
  static const _placeholder = '​​​​';

  late final TextEditingController _text = TextEditingController(text: _placeholder);

  @override
  void initState() {
    super.initState();
    _reset();
    widget.focusNode.onKeyEvent = _onKey;
  }

  @override
  void didUpdateWidget(TerminalKeyboard old) {
    super.didUpdateWidget(old);
    widget.focusNode.onKeyEvent = _onKey;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reset() {
    _text.value = const TextEditingValue(
      text: _placeholder,
      selection: TextSelection.collapsed(offset: _placeholder.length),
    );
  }

  /// Works out what changed in the hidden field and sends it.
  void _onChanged(String value) {
    var common = 0;
    while (common < value.length && common < _placeholder.length && value.codeUnitAt(common) == _placeholder.codeUnitAt(common)) {
      common++;
    }
    final deleted = _placeholder.length - common;
    final inserted = value.substring(common).replaceAll('​', '');
    for (var i = 0; i < deleted; i++) {
      widget.controller.key(TerminalKey.backspace);
    }
    _sendTyped(inserted);
    _reset();
  }

  void _sendTyped(String text) {
    if (text.isEmpty) return;
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) widget.controller.type(parts[i]);
      if (i < parts.length - 1) widget.controller.key(TerminalKey.enter);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final mods = KeyModifiers(ctrl: keys.isControlPressed, alt: keys.isAltPressed, shift: keys.isShiftPressed);
    final special = _HardwareKeys.special[event.logicalKey];
    if (special != null) {
      widget.controller.keyWith(special, mods);
      return KeyEventResult.handled;
    }
    // Ctrl/Alt with a character: send it ourselves, the text field would
    // otherwise treat it as a shortcut (select all, copy...).
    final char = event.character ?? event.logicalKey.keyLabel;
    if ((mods.ctrl || mods.alt) && char.length == 1) {
      // Ctrl+Shift+C / V copy and paste, like desktop terminals.
      if (mods.ctrl && mods.shift && event.logicalKey == LogicalKeyboardKey.keyV) {
        widget.controller.pasteClipboard();
        return KeyEventResult.handled;
      }
      widget.controller.textWith(char.toLowerCase(), KeyModifiers(ctrl: mods.ctrl, alt: mods.alt, shift: false));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        // The hidden field: tiny, transparent, but focusable.
        Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _text,
              focusNode: widget.focusNode,
              onChanged: _onChanged,
              onSubmitted: (_) {
                widget.controller.key(TerminalKey.enter);
                _reset();
              },
              // Keep the keyboard open after Enter and after taps elsewhere.
              onEditingComplete: () {},
              onTapOutside: (_) {},
              // No suggestions, no autocorrect, no capital letters: a phone
              // keyboard in "password" mode sends plain keys.
              keyboardType: widget.systemKeyboard ? TextInputType.visiblePassword : TextInputType.none,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              textCapitalization: TextCapitalization.none,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(fontSize: 1, color: Colors.transparent),
              decoration: const InputDecoration.collapsed(hintText: ''),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hardware keys that map to terminal keys.
abstract final class _HardwareKeys {
  static final special = <LogicalKeyboardKey, TerminalKey>{
    LogicalKeyboardKey.enter: TerminalKey.enter,
    LogicalKeyboardKey.numpadEnter: TerminalKey.enter,
    LogicalKeyboardKey.tab: TerminalKey.tab,
    LogicalKeyboardKey.backspace: TerminalKey.backspace,
    LogicalKeyboardKey.escape: TerminalKey.escape,
    LogicalKeyboardKey.arrowUp: TerminalKey.up,
    LogicalKeyboardKey.arrowDown: TerminalKey.down,
    LogicalKeyboardKey.arrowLeft: TerminalKey.left,
    LogicalKeyboardKey.arrowRight: TerminalKey.right,
    LogicalKeyboardKey.home: TerminalKey.home,
    LogicalKeyboardKey.end: TerminalKey.end,
    LogicalKeyboardKey.pageUp: TerminalKey.pageUp,
    LogicalKeyboardKey.pageDown: TerminalKey.pageDown,
    LogicalKeyboardKey.insert: TerminalKey.insert,
    LogicalKeyboardKey.delete: TerminalKey.delete,
    LogicalKeyboardKey.f1: TerminalKey.f1,
    LogicalKeyboardKey.f2: TerminalKey.f2,
    LogicalKeyboardKey.f3: TerminalKey.f3,
    LogicalKeyboardKey.f4: TerminalKey.f4,
    LogicalKeyboardKey.f5: TerminalKey.f5,
    LogicalKeyboardKey.f6: TerminalKey.f6,
    LogicalKeyboardKey.f7: TerminalKey.f7,
    LogicalKeyboardKey.f8: TerminalKey.f8,
    LogicalKeyboardKey.f9: TerminalKey.f9,
    LogicalKeyboardKey.f10: TerminalKey.f10,
    LogicalKeyboardKey.f11: TerminalKey.f11,
    LogicalKeyboardKey.f12: TerminalKey.f12,
  };
}
