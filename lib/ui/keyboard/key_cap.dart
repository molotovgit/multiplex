import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'key_face.dart';
import 'key_press_tracker.dart';
import 'key_spec.dart';
import 'keyboard_engine.dart';
import 'keyboard_modifiers.dart';
import 'keyboard_style.dart';

/// One key that reacts to touch: tap, long press for alternates, swipe up,
/// hold to repeat, and drag on the space bar to move the cursor. Uses raw
/// pointer events, so a press responds at once and never takes focus away
/// from the terminal.
class KeyCap extends StatefulWidget {
  const KeyCap({super.key, required this.spec, required this.engine, required this.look, this.inScrollingRow = false});

  final KeySpec spec;
  final KeyboardEngine engine;
  final KeyLook look;

  /// The key is in the sideways-scrolling terminal row.
  final bool inScrollingRow;

  @override
  State<KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<KeyCap> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final _tracker = KeyPressTracker(
    onSend: (key) => widget.engine.press(key),
    onCursor: (arrow) => widget.engine.moveCursor(arrow),
  )..addListener(_onTrackerChanged);
  int? _pointer;

  /// Keeps popups clear of the screen edges.
  static const _edge = 4.0;

  /// The narrowest cell in the alternates popup.
  static const _minCell = 44.0;

  KeyboardEngine get _engine => widget.engine;

  @override
  void dispose() {
    _tracker.dispose();
    super.dispose();
  }

  void _onTrackerChanged() {
    if (!mounted) return;
    final wantsOverlay = _tracker.phase == PressPhase.choosing || (_engine.settings.keyPreview && (_tracker.previewKey?.previews ?? false));
    if (wantsOverlay) {
      _portal.show();
    } else {
      _portal.hide();
    }
    setState(() {});
  }

  /// Where the popup goes for this key, kept inside the screen.
  ChoiceGeometry? _geometry() {
    final count = widget.spec.alternates.length;
    final box = context.findRenderObject() as RenderBox?;
    if (count == 0 || box == null || !box.hasSize) return null;
    final cell = math.max(box.size.width, _minCell);
    return ChoiceGeometry(left: _clampedLeft(box, cell * count), cell: cell, count: count);
  }

  /// A popup of [width] centred over the key, shifted to stay on screen.
  double _clampedLeft(RenderBox box, double width) {
    final keyLeft = box.localToGlobal(Offset.zero).dx;
    final screen = MediaQuery.sizeOf(context).width;
    final wanted = keyLeft + (box.size.width - width) / 2;
    final clamped = wanted.clamp(_edge, math.max(_edge, screen - width - _edge));
    return clamped - keyLeft;
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _engine.touchFeedback();
    _tracker.down(
      event.localPosition,
      widget.spec,
      options: PressOptions(
        swipe: _engine.settings.swipeForSymbols,
        swipeDistance: widget.look.metrics.rowHeight * 0.45,
        inScrollingRow: widget.inScrollingRow,
      ),
      geometry: _geometry(),
    );
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _pointer) _tracker.move(event.localPosition);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _tracker.up();
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _tracker.cancel();
  }

  ModifierMode? get _mode => switch (widget.spec.action) {
        ToggleModifier(:final modifier) => _engine.modifiers.modeOf(modifier),
        _ => null,
      };

  String get _spokenLabel {
    final name = widget.spec.spokenFor(shift: _engine.shiftOn);
    return switch (_mode) {
      ModifierMode.locked => '$name, locked',
      ModifierMode.oneShot => '$name, on for the next key',
      _ => name,
    };
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    return Semantics(
      button: true,
      label: _spokenLabel,
      toggled: mode == null ? null : mode != ModifierMode.off,
      hint: widget.spec.alternates.isEmpty ? null : 'Hold for more characters',
      onTap: () => _engine.press(widget.spec),
      excludeSemantics: true,
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _overlay,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: KeyFace(
              spec: widget.spec,
              look: widget.look,
              pressed: _tracker.isDown,
              shift: _engine.shiftOn,
              mode: mode,
            ),
          ),
        ),
      ),
    );
  }

  /// The alternates popup or the preview bubble, just above the key.
  Widget _overlay(BuildContext context) {
    final box = this.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const SizedBox.shrink();
    final metrics = widget.look.metrics;
    final geometry = _tracker.geometry;
    final Widget child;
    final double left;
    if (_tracker.phase == PressPhase.choosing && geometry != null) {
      left = geometry.left;
      child = KeyAlternatesPopup(
        keys: widget.spec.alternates,
        choice: _tracker.choice,
        cell: geometry.cell,
        height: metrics.rowHeight,
        look: widget.look,
      );
    } else {
      final key = _tracker.previewKey;
      if (key == null) return const SizedBox.shrink();
      final size = Size(math.max(box.size.width + 12, _minCell), metrics.rowHeight * 1.1);
      left = _clampedLeft(box, size.width);
      child = KeyPreviewBubble(label: key.labelFor(shift: _engine.shiftOn), look: widget.look, size: size);
    }
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: Offset(left, KeyboardMetrics.gapY),
        child: IgnorePointer(child: child),
      ),
    );
  }
}
