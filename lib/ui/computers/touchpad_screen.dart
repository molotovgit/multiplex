import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_motion.dart';
import '../../app/screen_awake.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../data/models.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/touchpad_controller.dart';
import '../../src/rust/api/touchpad.dart';
import '../desktop/desktop_controls.dart';
import '../desktop/desktop_key_sink.dart';
import '../hosts/host_connector.dart';
import '../keyboard/terminal_keyboard_panel.dart';
import '../settings/settings_widgets.dart';

/// The phone as the computer's touchpad and keyboard, without its
/// picture: for when the computer's screen is in sight (a TV, a desk
/// across the room). Nothing is decoded, so it is as quick as the network.
class TouchpadScreen extends StatefulWidget {
  const TouchpadScreen({super.key, required this.title, required this.open});

  /// The computer's name.
  final String title;

  /// Starts the computer's side. Tests pass a stand-in.
  final Future<TouchpadPipe> Function() open;

  /// Connects (if needed) and opens the touchpad.
  static Future<void> show(BuildContext context, Host host) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TouchpadScreen(title: host.title, open: () => RustTouchpadPipe.open(session.ssh)),
      ),
    );
  }

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  late final TouchpadController _pad = TouchpadController(widget.open)..start();
  bool _keyboard = false;

  @override
  void initState() {
    super.initState();
    ScreenAwake.hold();
  }

  @override
  void dispose() {
    ScreenAwake.release();
    _pad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} touchpad'),
        actions: [
          IconButton(
            tooltip: _keyboard ? 'Hide keyboard' : 'Keyboard',
            isSelected: _keyboard,
            icon: const Icon(Icons.keyboard_outlined),
            selectedIcon: const Icon(Icons.keyboard_hide_outlined),
            onPressed: () => setState(() => _keyboard = !_keyboard),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _pad,
        builder: (context, _) {
          final problem = _pad.problem;
          if (!_pad.ready) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: problem == null
                    ? const BusyNote('Starting the touchpad on the computer…')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NoticeBox(tone: NoticeTone.error, text: problem),
                          const SizedBox(height: 12),
                          FilledButton.tonal(onPressed: _pad.start, child: const Text('Try again')),
                        ],
                      ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TouchpadSurface(controller: _pad),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _HoldButton(label: 'Left click', button: TouchpadButton.left, controller: _pad),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HoldButton(label: 'Right click', button: TouchpadButton.right, controller: _pad),
                    ),
                  ],
                ),
              ),
              // Multiplex's keyboard slides up under the Super key bar.
              AnimatedSize(
                duration: motion.sheet.duration ?? Duration.zero,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DesktopKeyBar(controller: _pad, keepFocus: () {}, compact: _keyboard),
                    if (_keyboard)
                      TerminalKeyboardPanel.withSink(
                        showCommands: false,
                        sink: DesktopKeySink(_pad),
                        onSnippets: () {},
                        onHistory: () {},
                        onHide: () => setState(() => _keyboard = false),
                        onSwitchToSystem: () {},
                      )
                    else
                      SizedBox(height: MediaQuery.paddingOf(context).bottom),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A mouse button under the thumb: press and hold it to drag with the
/// other hand on the touchpad.
class _HoldButton extends StatelessWidget {
  const _HoldButton({required this.label, required this.button, required this.controller});

  final String label;
  final TouchpadButton button;
  final TouchpadController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: () => controller.click(button),
      child: Listener(
        onPointerDown: (_) {
          HapticFeedback.selectionClick();
          controller.press(button);
        },
        onPointerUp: (_) => controller.release(button),
        onPointerCancel: (_) => controller.release(button),
        child: Material(
          color: look.surfaces.card,
          shape: look.shapes.border(look.shapes.card, look.surfaces.side),
          child: SizedBox(
            height: 48,
            child: Center(
              child: ExcludeSemantics(
                child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.text)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The touch area. One finger moves the pointer, a tap clicks, holding
/// still and then moving drags; two fingers scroll, a two-finger tap is
/// the right button, a three-finger tap the middle one.
class TouchpadSurface extends StatefulWidget {
  const TouchpadSurface({super.key, required this.controller});

  final TouchpadController controller;

  @override
  State<TouchpadSurface> createState() => _TouchpadSurfaceState();
}

class _TouchpadSurfaceState extends State<TouchpadSurface> {
  static const _tapSlop = 10.0;
  static const _tapTime = Duration(milliseconds: 260);
  static const _holdTime = Duration(milliseconds: 420);

  final Map<int, Offset> _fingers = {};
  DateTime _startAt = DateTime.now();
  Offset _start = Offset.zero;

  /// The most fingers down at once in this gesture.
  int _most = 0;
  bool _moved = false;
  Timer? _hold;

  TouchpadController get c => widget.controller;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (_fingers.isEmpty) {
      _startAt = DateTime.now();
      _start = e.localPosition;
      _most = 0;
      _moved = false;
      // Held still: what follows is a drag.
      _hold = Timer(_holdTime, () {
        if (_fingers.length == 1 && !_moved && mounted) {
          HapticFeedback.mediumImpact();
          c.press(TouchpadButton.left);
        }
      });
    } else {
      _hold?.cancel();
    }
    _fingers[e.pointer] = e.localPosition;
    if (_fingers.length > _most) _most = _fingers.length;
  }

  void _move(PointerMoveEvent e) {
    final before = _fingers[e.pointer];
    if (before == null) return;
    _fingers[e.pointer] = e.localPosition;
    if (!_moved && (e.localPosition - _start).distance > _tapSlop) {
      _moved = true;
      if (!c.dragging) _hold?.cancel();
    }
    if (!_moved) return;
    final delta = e.localPosition - before;
    if (_fingers.length == 1) {
      c.moveBy(delta);
    } else if (_fingers.length == 2) {
      // Each of the two fingers reports its own movement: half each.
      c.scrollBy(delta / 2);
    }
  }

  void _up(PointerEvent e) {
    if (_fingers.remove(e.pointer) == null || _fingers.isNotEmpty) return;
    _hold?.cancel();
    if (c.dragging) {
      c.release(TouchpadButton.left);
      return;
    }
    final quick = DateTime.now().difference(_startAt) < _tapTime;
    if (_moved || !quick || e is PointerCancelEvent) return;
    HapticFeedback.selectionClick();
    c.click(switch (_most) {
      1 => TouchpadButton.left,
      2 => TouchpadButton.right,
      _ => TouchpadButton.middle,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Touchpad',
      hint: 'Drag to move the pointer, tap to click',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => AnimatedContainer(
            duration: AppMotion.of(context).theme ~/ 2,
            decoration: ShapeDecoration(
              color: look.surfaces.card,
              shape: look.shapes.border(look.shapes.card, c.dragging ? BorderSide(color: colors.accent, width: 2) : look.surfaces.side),
            ),
            child: Center(
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    c.dragging
                        ? 'Dragging: lift the finger to let go'
                        : 'Drag to move · tap to click · hold, then drag\nTwo fingers: scroll, tap for the right button',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: c.dragging ? colors.accent : colors.muted),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
