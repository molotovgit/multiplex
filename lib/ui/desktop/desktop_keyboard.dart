import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sessions/desktop_controller.dart';
import 'desktop_keys.dart';

/// Receives typing for the remote desktop.
///
/// Like the terminal, a hidden text field holds the focus, so the phone's
/// keyboard can talk to it; its invisible placeholder characters tell
/// typing from Backspace. A hardware keyboard bypasses the field: every
/// key goes to the desktop as itself, press and release, so shortcuts and
/// holding keys work as at the desk.
class DesktopKeyboard extends StatefulWidget {
  const DesktopKeyboard({super.key, required this.controller, required this.focusNode, required this.child, this.systemKeyboard = true});

  /// False while Multiplex's own keyboard is shown: the hidden field keeps
  /// the focus (a hardware keyboard still works) but the phone's keyboard
  /// stays closed.
  final bool systemKeyboard;

  final DesktopController controller;
  final FocusNode focusNode;
  final Widget child;

  @override
  State<DesktopKeyboard> createState() => _DesktopKeyboardState();
}

class _DesktopKeyboardState extends State<DesktopKeyboard> {
  /// Zero-width spaces: invisible, and phone keyboards can delete them.
  static const _placeholder = '​​​​';

  late final TextEditingController _text = TextEditingController(text: _placeholder);

  /// Hardware keys that are down, so each release goes out too.
  final Set<int> _down = {};

  @override
  void initState() {
    super.initState();
    _reset();
    widget.focusNode.onKeyEvent = _onKey;
  }

  @override
  void didUpdateWidget(DesktopKeyboard old) {
    super.didUpdateWidget(old);
    widget.focusNode.onKeyEvent = _onKey;
  }

  @override
  void dispose() {
    for (final code in _down) {
      widget.controller.keyEvent(code, false);
    }
    _text.dispose();
    super.dispose();
  }

  void _reset() {
    _text.value = const TextEditingValue(
      text: _placeholder,
      selection: TextSelection.collapsed(offset: _placeholder.length),
    );
  }

  void _onChanged(String value) {
    var common = 0;
    while (common < value.length && common < _placeholder.length && value.codeUnitAt(common) == _placeholder.codeUnitAt(common)) {
      common++;
    }
    final deleted = _placeholder.length - common;
    final inserted = value.substring(common).replaceAll('​', '');
    for (var i = 0; i < deleted; i++) {
      widget.controller.tap(LinuxKey.backspace);
    }
    widget.controller.type(inserted);
    _reset();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final code = HardwareKeys.code(event.physicalKey);
    if (code == null) return KeyEventResult.ignored;
    // The remote repeats held keys itself.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    final pressed = event is KeyDownEvent;
    if (pressed) {
      _down.add(code);
    } else if (!_down.remove(code)) {
      return KeyEventResult.handled;
    }
    widget.controller.keyEvent(code, pressed);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
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
                widget.controller.tap(LinuxKey.enter);
                _reset();
              },
              onEditingComplete: () {},
              onTapOutside: (_) {},
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
