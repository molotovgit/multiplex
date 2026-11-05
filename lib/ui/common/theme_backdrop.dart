import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/backdrops/backdrop_images.dart';
import '../../app/backdrops/backdrop_painter.dart';
import '../../app/theme_backgrounds.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';

/// What shows behind text: a backdrop drawn from the theme's colours, a
/// picture from the theme's folder, or just the colour. Drawings and
/// pictures are blurred and dimmed with the theme's background colour,
/// so text on top stays readable.
class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({super.key, required this.theme, required this.slide, required this.color, this.dim = 0.4, this.blur = 0});

  final ThemeSpec theme;

  /// Null shows only the colour.
  final ThemeSlide? slide;

  /// The background colour; it also dims the drawing or picture.
  final Color color;
  final double dim;
  final double blur;

  /// Finds the dimming layer in tests.
  static const dimKey = ValueKey('backdrop-dim');

  @override
  Widget build(BuildContext context) {
    final Widget art = switch (slide) {
      null => const SizedBox.shrink(),
      PatternSlide(:final pattern) => _PatternImage(pattern: pattern, colors: BackdropColors.of(theme)),
      PictureSlide(:final name) => _PictureImage(themeId: theme.id, name: name),
    };
    if (slide == null) return ColoredBox(color: color);
    Widget layer = art;
    if (blur > 0) {
      layer = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp), child: layer);
    }
    // Its own layer: the drawing is not redrawn when the text on top changes.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: color),
          ExcludeSemantics(child: layer),
          ColoredBox(key: dimKey, color: color.withValues(alpha: dim)),
        ],
      ),
    );
  }
}

/// A drawn backdrop at the size of its box, from the shared image cache.
class _PatternImage extends StatefulWidget {
  const _PatternImage({required this.pattern, required this.colors});

  final BackdropPattern pattern;
  final BackdropColors colors;

  @override
  State<_PatternImage> createState() => _PatternImageState();
}

class _PatternImageState extends State<_PatternImage> {
  ui.Image? _image;
  Object? _drawnFor;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// This widget's own handle to the image for [size]; a new one only
  /// when the pattern, colours or size change.
  ui.Image? _imageFor(Size size, double ratio) {
    if (size.isEmpty || !size.isFinite) return null;
    final wanted = (widget.pattern, widget.colors, size, ratio);
    if (wanted != _drawnFor) {
      _image?.dispose();
      _image = BackdropImages.of(widget.pattern, widget.colors, size, ratio);
      _drawnFor = wanted;
    }
    return _image;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final image = _imageFor(constraints.biggest, ratio);
        if (image == null) return const SizedBox.shrink();
        // Drawn a little larger than the box, so it is cut, never stretched.
        return RawImage(image: image, fit: BoxFit.none, alignment: Alignment.topLeft, scale: ratio);
      },
    );
  }
}

/// A picture from the theme's folder; nothing while it is looked up or
/// when it is not on this device.
class _PictureImage extends StatefulWidget {
  const _PictureImage({required this.themeId, required this.name});

  final String themeId;
  final String name;

  @override
  State<_PictureImage> createState() => _PictureImageState();
}

class _PictureImageState extends State<_PictureImage> {
  File? _file;
  (String, String)? _loaded;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_PictureImage old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  Future<void> _resolve() async {
    final wanted = (widget.themeId, widget.name);
    if (wanted == _loaded) return;
    _loaded = wanted;
    final file = await ThemeBackgrounds.fileFor(widget.themeId, widget.name);
    if (mounted && _loaded == wanted) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return const SizedBox.shrink();
    // Decode no larger than the screen needs, to keep memory down.
    final media = MediaQuery.of(context);
    final width = (media.size.width * media.devicePixelRatio).round();
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: width > 0 ? width : null,
      gaplessPlayback: true,
      // A broken file shows the plain colour.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
