import 'package:flutter/material.dart';

/// The shaded, shiny look of early-2000s desktops for the glossy style:
/// bars banded like a title bar, buttons shaded from white, a green main
/// button with a rounded end, and an orange glow on press. The gradient
/// stops follow XP.css by Adam Hammad (MIT); the colours come from the
/// theme, so any theme can be glossy.
abstract final class Gloss {
  static Color lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
  static Color darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

  /// A bar in [c], banded like a title bar: a bright top edge, a long
  /// even middle, a lighter band low down and a dark bottom edge.
  static LinearGradient band(Color c) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lighten(c, 0.45), c, c, lighten(c, 0.12), lighten(c, 0.12), lighten(c, 0.04), darken(c, 0.22), darken(c, 0.22)],
        stops: const [0, 0.08, 0.40, 0.88, 0.93, 0.95, 0.96, 1],
      );

  /// A plain button or key on [face]: white at the top, shading down.
  static LinearGradient button(Color face) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lighten(face, 0.85), lighten(face, 0.25), darken(face, 0.09)],
        stops: const [0, 0.86, 1],
      );

  /// The same button held down: darker at the top, as if pushed in.
  static LinearGradient pressed(Color face) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [darken(face, 0.13), darken(face, 0.04), darken(face, 0.03), lighten(face, 0.4)],
        stops: const [0, 0.08, 0.94, 1],
      );

  /// The screen's main button, in [green]: like a start button.
  static LinearGradient go(Color green) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lighten(green, 0.5), lighten(green, 0.15), green, darken(green, 0.08), darken(green, 0.25)],
        stops: const [0, 0.14, 0.45, 0.88, 1],
      );

  /// The glow around a button under the finger or the keyboard focus.
  static const glow = Color(0xFFE5A01A);

  /// How long a press takes to show.
  static const press = Duration(milliseconds: 90);

  /// A button style: shaded face, thin dark edge, rounded a little, and
  /// pushed in with an orange glow while held.
  static ButtonStyle buttonStyle({required Color face, required Color edge, required Color text, double radius = 3}) => ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStatePropertyAll(text),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: edge)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius))),
        backgroundBuilder: (context, states, child) {
          final down = states.contains(WidgetState.pressed);
          final lit = down || states.contains(WidgetState.hovered) || states.contains(WidgetState.focused);
          return AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : press,
            decoration: BoxDecoration(
              gradient: down ? pressed(face) : button(face),
              borderRadius: BorderRadius.circular(radius),
              border: lit ? Border.all(color: glow, width: 2) : null,
            ),
            child: child,
          );
        },
      );
}

/// A shape with a shine: its edge, plus light across the top half, as on
/// glossy bars and buttons. Drawn over the content, so it suits bars and
/// buttons whose text is light.
class GlossBorder extends OutlinedBorder {
  const GlossBorder({this.radius = BorderRadius.zero, super.side});

  final BorderRadius radius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  RRect _rrect(Rect rect) => radius.toRRect(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect).deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final outer = _rrect(rect);
    canvas.save();
    canvas.clipRRect(outer);
    final top = Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + rect.height * 0.5);
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.42), Colors.white.withValues(alpha: 0.08)],
        ).createShader(top),
    );
    canvas.restore();
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(outer.deflate(side.width / 2), side.toPaint());
    }
  }

  @override
  GlossBorder copyWith({BorderSide? side, BorderRadius? radius}) => GlossBorder(radius: radius ?? this.radius, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => GlossBorder(radius: radius * t, side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is GlossBorder ? GlossBorder(radius: BorderRadius.lerp(a.radius, radius, t)!, side: BorderSide.lerp(a.side, side, t)) : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is GlossBorder ? GlossBorder(radius: BorderRadius.lerp(radius, b.radius, t)!, side: BorderSide.lerp(side, b.side, t)) : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) => other is GlossBorder && other.radius == radius && other.side == side;

  @override
  int get hashCode => Object.hash(radius, side);
}
