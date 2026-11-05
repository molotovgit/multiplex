import 'dart:math' as math;
import 'dart:ui' as ui;

import '../theme_style.dart';
import 'backdrop_painter.dart';

/// One drawn backdrop: what was drawn, and at what size.
class _ImageKey {
  const _ImageKey(this.pattern, this.colors, this.width, this.height, this.ratio);

  final BackdropPattern pattern;
  final BackdropColors colors;
  final int width, height;
  final double ratio;

  @override
  bool operator ==(Object other) =>
      other is _ImageKey &&
      other.pattern == pattern &&
      other.colors == colors &&
      other.width == width &&
      other.height == height &&
      other.ratio == ratio;

  @override
  int get hashCode => Object.hash(pattern, colors, width, height, ratio);
}

/// Draws backdrops into images at screen size, once, and keeps the last
/// few. Each caller gets its own handle ([ui.Image.clone]) and disposes it;
/// the cache disposes its own when it drops an image.
abstract final class BackdropImages {
  /// A few screens' worth: the terminal, the main screens and a rotation.
  static const _keep = 6;

  /// Sizes are rounded up to steps of this many logical pixels, so small
  /// layout changes reuse the same image.
  static const _bucket = 64.0;

  /// The largest side drawn, in physical pixels.
  static const _maxSide = 4096;

  /// Oldest first: a map keeps the order things were put in.
  static final _images = <_ImageKey, ui.Image>{};

  /// A handle to the image of [pattern] in [colors] for a box of [size]
  /// logical pixels at [pixelRatio]. The caller disposes it.
  static ui.Image of(BackdropPattern pattern, BackdropColors colors, ui.Size size, double pixelRatio) {
    final logical = ui.Size(_round(size.width), _round(size.height));
    final ratio = math.min(pixelRatio, _maxSide / math.max(logical.width, logical.height));
    final key = _ImageKey(pattern, colors, logical.width.round(), logical.height.round(), ratio);
    var image = _images.remove(key);
    image ??= _draw(pattern, colors, logical, ratio);
    _images[key] = image;
    while (_images.length > _keep) {
      final oldest = _images.keys.first;
      _images.remove(oldest)!.dispose();
    }
    return image.clone();
  }

  /// Draws without caching, for tests and one-off use.
  static ui.Image draw(BackdropPattern pattern, BackdropColors colors, ui.Size size, double ratio) => _draw(pattern, colors, size, ratio);

  static double _round(double v) => math.max(_bucket, (v / _bucket).ceil() * _bucket);

  static ui.Image _draw(BackdropPattern pattern, BackdropColors colors, ui.Size size, double ratio) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(ratio);
    BackdropPainter.of(pattern).paint(canvas, size, colors);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((size.width * ratio).round(), (size.height * ratio).round());
    picture.dispose();
    return image;
  }
}
