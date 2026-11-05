import 'dart:math' as math;
import 'dart:ui';

import 'backdrop_painter.dart';

/// Soft blobs of the theme's colours melting into each other.
class MeshPainter extends BackdropPainter {
  const MeshPainter();

  @override
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random) {
    final longest = math.max(size.width, size.height);
    final blobs = [colors.accent, ...colors.hues.take(3)];
    for (final color in blobs) {
      final centre = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
      final radius = longest * (0.35 + random.nextDouble() * 0.35);
      final paint = Paint()
        ..shader = Gradient.radial(centre, radius, [color.withValues(alpha: 0.30), color.withValues(alpha: 0)]);
      canvas.drawCircle(centre, radius, paint);
    }
  }
}

/// A fine grid of dots, a few of them in the accent colour.
class DotGridPainter extends BackdropPainter {
  const DotGridPainter();

  static const spacing = 22.0;

  @override
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random) {
    final ink = Paint()..color = colors.ink.withValues(alpha: 0.16);
    final accent = Paint()..color = colors.accent.withValues(alpha: 0.45);
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        final lit = random.nextDouble() < 0.025;
        canvas.drawCircle(Offset(x, y), lit ? 1.8 : 1.1, lit ? accent : ink);
      }
    }
  }
}

/// Thin diagonal lines with a faint glow at the top, like an old screen.
class ScanlinePainter extends BackdropPainter {
  const ScanlinePainter();

  static const spacing = 7.0;

  @override
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random) {
    final glow = Paint()
      ..shader = Gradient.linear(Offset.zero, Offset(0, size.height * 0.6), [colors.accent.withValues(alpha: 0.14), colors.accent.withValues(alpha: 0)]);
    canvas.drawRect(Offset.zero & size, glow);
    final line = Paint()
      ..color = colors.ink.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    // Lines at 45 degrees cover the box when they start from beyond its left.
    for (var start = -size.height; start < size.width; start += spacing) {
      canvas.drawLine(Offset(start, size.height), Offset(start + size.height, 0), line);
    }
  }
}

/// Wobbly rings around a few centres, like the contour lines of a map.
class TopoPainter extends BackdropPainter {
  const TopoPainter();

  static const step = 26.0;

  @override
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random) {
    final longest = math.max(size.width, size.height);
    for (var hill = 0; hill < 3; hill++) {
      final centre = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (hill == 0 ? colors.accent : colors.ink).withValues(alpha: hill == 0 ? 0.20 : 0.10);
      final phase = random.nextDouble() * math.pi * 2;
      final lobes = 3 + random.nextInt(3);
      for (var r = step; r < longest * 0.7; r += step) {
        canvas.drawPath(_ring(centre, r, phase + r / 90, lobes), paint);
      }
    }
  }

  Path _ring(Offset centre, double radius, double phase, int lobes) {
    final path = Path();
    const points = 72;
    for (var i = 0; i <= points; i++) {
      final angle = i / points * math.pi * 2;
      final r = radius + math.sin(angle * lobes + phase) * radius * 0.08;
      final p = centre + Offset(math.cos(angle) * r, math.sin(angle) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }
}

/// Triangles in gently shifted tones of the background, like cut glass.
class FacetPainter extends BackdropPainter {
  const FacetPainter();

  static const cell = 120.0;

  @override
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random) {
    final cols = (size.width / cell).ceil() + 1, rows = (size.height / cell).ceil() + 1;
    // Corner points, nudged at random so no two triangles match.
    final points = [
      for (var r = 0; r <= rows; r++)
        [
          for (var c = 0; c <= cols; c++)
            Offset(
              c * cell + (c == 0 || c == cols ? 0 : (random.nextDouble() - 0.5) * cell * 0.6),
              r * cell + (r == 0 || r == rows ? 0 : (random.nextDouble() - 0.5) * cell * 0.6),
            ),
        ],
    ];
    final tones = [colors.accent, ...colors.hues, colors.ink];
    final paint = Paint();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final a = points[r][c], b = points[r][c + 1], d = points[r + 1][c], e = points[r + 1][c + 1];
        for (final triangle in [
          [a, b, e],
          [a, e, d],
        ]) {
          final tone = tones[random.nextInt(tones.length)];
          paint.color = Color.lerp(colors.background, tone, 0.03 + random.nextDouble() * 0.09)!;
          canvas.drawPath(Path()..addPolygon(triangle, true), paint);
        }
      }
    }
  }
}

/// Small stars of different brightness over a faint glow.
class StarfieldPainter extends BackdropPainter {
  const StarfieldPainter();

  /// One star for about this many square logical pixels.
  static const density = 1800.0;

  @override
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random) {
    final glowCentre = Offset(size.width * (0.2 + random.nextDouble() * 0.6), size.height * (0.2 + random.nextDouble() * 0.5));
    final glowRadius = math.max(size.width, size.height) * 0.6;
    canvas.drawCircle(
      glowCentre,
      glowRadius,
      Paint()..shader = Gradient.radial(glowCentre, glowRadius, [colors.accent.withValues(alpha: 0.14), colors.accent.withValues(alpha: 0)]),
    );
    final count = (size.width * size.height / density).round();
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final special = random.nextDouble() < 0.04;
      final color = special ? colors.hues[random.nextInt(colors.hues.length)] : colors.ink;
      paint.color = color.withValues(alpha: 0.15 + random.nextDouble() * (special ? 0.7 : 0.5));
      final radius = 0.4 + random.nextDouble() * (special ? 1.6 : 1.0);
      canvas.drawCircle(Offset(random.nextDouble() * size.width, random.nextDouble() * size.height), radius, paint);
    }
  }
}

/// A sky over rolling green hills, drawn in the theme's accent and green.
class HillsPainter extends BackdropPainter {
  const HillsPainter();

  @override
  void draw(Canvas canvas, Size size, BackdropColors colors, math.Random random) {
    final sky = Offset.zero & size;
    canvas.drawRect(
      sky,
      Paint()
        ..shader = Gradient.linear(Offset.zero, Offset(0, size.height * 0.75), [
          Color.lerp(colors.accent, const Color(0xFFFFFFFF), 0.35)!,
          Color.lerp(colors.accent, const Color(0xFFFFFFFF), 0.85)!,
        ]),
    );
    final green = colors.hues[3];
    // Three hills, the far ones paler, each a long soft curve.
    for (final (i, top) in [0.58, 0.66, 0.76].indexed) {
      final y = size.height * top;
      final rise = size.height * (0.08 + random.nextDouble() * 0.06);
      final peak = size.width * (0.2 + random.nextDouble() * 0.6);
      final path = Path()
        ..moveTo(0, y + rise * 0.6)
        ..quadraticBezierTo(peak, y - rise, size.width, y + rise * 0.3)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final shade = Color.lerp(green, const Color(0xFFFFFFFF), 0.45 - i * 0.18)!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = Gradient.linear(Offset(0, y - rise), Offset(0, size.height), [
            Color.lerp(shade, const Color(0xFFFFFFFF), 0.2)!,
            Color.lerp(shade, const Color(0xFF000000), 0.15)!,
          ]),
      );
    }
  }
}
