import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/terminal_backgrounds.dart';
import '../../app/theme_style.dart';

/// What is behind the terminal text: the theme's background colour, or a
/// picture, blurred and dimmed with that colour so the text stays
/// readable.
class TerminalBackdrop extends StatefulWidget {
  const TerminalBackdrop({super.key, required this.style, required this.color});

  final TerminalStyle style;

  /// The terminal's background colour; it also dims the picture.
  final Color color;

  /// Finds the dimming layer in tests.
  static const dimKey = ValueKey('terminal-dim');

  @override
  State<TerminalBackdrop> createState() => _TerminalBackdropState();
}

class _TerminalBackdropState extends State<TerminalBackdrop> {
  File? _file;
  String? _loadedName;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(TerminalBackdrop old) {
    super.didUpdateWidget(old);
    if (old.style.backgroundImage != widget.style.backgroundImage) _resolve();
  }

  /// Finds the picture's file; a missing file simply shows the colour.
  Future<void> _resolve() async {
    final name = widget.style.backgroundImage;
    if (name == _loadedName) return;
    _loadedName = name;
    final file = name == null ? null : await TerminalBackgrounds.fileFor(name);
    if (mounted && _loadedName == name) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.style.hasImage ? _file : null;
    if (file == null) return ColoredBox(color: widget.color);
    final blur = widget.style.blur;
    // Decode no larger than the screen needs, to keep memory down.
    final media = MediaQuery.of(context);
    final width = (media.size.width * media.devicePixelRatio).round();
    Widget picture = Image.file(file, fit: BoxFit.cover, cacheWidth: width > 0 ? width : null, gaplessPlayback: true);
    if (blur > 0) {
      picture = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp), child: picture);
    }
    // Its own layer: the picture is not redrawn when the text changes.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: widget.color),
          ExcludeSemantics(child: picture),
          ColoredBox(key: TerminalBackdrop.dimKey, color: widget.color.withValues(alpha: widget.style.dim)),
        ],
      ),
    );
  }
}
