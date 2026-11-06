import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'pdf_document.dart';
import 'zoom_view.dart';

/// A PDF one page at a time: swipe sideways between pages, pinch to zoom.
/// Buttons do the same for people who cannot swipe.
class PdfViewer extends StatefulWidget {
  const PdfViewer({super.key, required this.document});

  final PdfDocument document;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  final _pages = PageController();
  int _page = 0;

  /// Swiping is off while a page is zoomed in, so dragging moves around
  /// the page instead of turning it.
  bool _zoomed = false;

  /// Drawn pages, the most recent few only, to keep memory low.
  final _drawn = <int, Future<Uint8List>>{};
  static const _keep = 5;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<Uint8List> _render(int index, int width) {
    final ready = _drawn.remove(index) ?? widget.document.render(index, width);
    _drawn[index] = ready;
    while (_drawn.length > _keep) {
      _drawn.remove(_drawn.keys.first);
    }
    return ready;
  }

  void _go(int page) {
    if (page < 0 || page >= widget.document.pageCount) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final count = widget.document.pageCount;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Drawn at twice the screen's pixels so zooming in stays sharp,
              // within what a phone's memory handles well.
              final ratio = MediaQuery.devicePixelRatioOf(context);
              final width = math.min(2400, (constraints.maxWidth * ratio * 2).round());
              return PageView.builder(
                controller: _pages,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: count,
                onPageChanged: (page) => setState(() {
                  _page = page;
                  _zoomed = false;
                }),
                itemBuilder: (context, index) => _PdfPage(
                  key: ValueKey(index),
                  size: widget.document.pageSizes[index],
                  picture: _render(index, width),
                  number: index + 1,
                  onZoomed: (zoomed) => setState(() => _zoomed = zoomed),
                ),
              );
            },
          ),
        ),
        Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(tooltip: 'Previous page', icon: const Icon(Icons.chevron_left), onPressed: _page > 0 ? () => _go(_page - 1) : null),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text('Page ${_page + 1} of $count', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ),
                IconButton(tooltip: 'Next page', icon: const Icon(Icons.chevron_right), onPressed: _page + 1 < count ? () => _go(_page + 1) : null),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One page: a plain sheet the shape of the page while it is drawn, then
/// the picture.
class _PdfPage extends StatelessWidget {
  const _PdfPage({super.key, required this.size, required this.picture, required this.number, required this.onZoomed});

  final Size size;
  final Future<Uint8List> picture;
  final int number;
  final ValueChanged<bool> onZoomed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final aspect = size.height > 0 ? size.width / size.height : 0.7;
    return ZoomView(
      onZoomed: onZoomed,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: aspect,
            child: FutureBuilder<Uint8List>(
              future: picture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (snapshot.hasError) {
                  return ColoredBox(
                    color: colors.raised,
                    child: Center(child: Text('Page $number could not be drawn.', style: TextStyle(color: colors.muted))),
                  );
                }
                if (bytes == null) {
                  return ColoredBox(color: colors.raised, child: const Center(child: CircularProgressIndicator()));
                }
                return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true, semanticLabel: 'Page $number');
              },
            ),
          ),
        ),
      ),
    );
  }
}
