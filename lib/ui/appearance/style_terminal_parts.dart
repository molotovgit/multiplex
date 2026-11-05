import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme_backgrounds.dart';
import '../../app/theme_look.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';
import '../common/widgets.dart';
import 'style_controls.dart';
import 'style_section.dart';

/// The terminal part of a style: space around the text and the tab strip.
class TerminalStyleControls extends StatelessWidget {
  const TerminalStyleControls({super.key, required this.style, required this.onChanged});

  final TerminalStyle style;
  final ValueChanged<TerminalStyle> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Terminal'),
          StyleChoice(
            title: 'Space around the text',
            options: StyleOptions.paddings,
            selected: style.padding,
            onChanged: (v) => onChanged(style.copyWith(padding: v)),
          ),
          SwitchListTile(
            title: const Text('Terminal tabs'),
            subtitle: const Text('Shows the connection\'s terminals in a strip above the text'),
            value: style.showTabs,
            onChanged: (v) => onChanged(style.copyWith(showTabs: v)),
          ),
        ],
      );
}

/// A theme's background pictures, like the wallpapers of a theme pack:
/// add and remove them, pick the one that shows now, and set how they are
/// dimmed and blurred. Pictures are copied into the theme's own folder.
class BackgroundsSection extends StatelessWidget {
  const BackgroundsSection({super.key, required this.theme, required this.onChanged});

  final ThemeSpec theme;
  final ValueChanged<ThemeSpec> onChanged;

  Future<void> _add(BuildContext context) async {
    try {
      final added = await ThemeBackgrounds.pick(theme.id);
      if (added.isEmpty) return;
      final all = [...theme.backgrounds, ...added].take(ThemeSpec.maxBackgrounds).toList();
      onChanged(theme.copyWith(backgrounds: all, activeBackground: theme.activeBackground));
    } on BackgroundFileException catch (e) {
      if (context.mounted) Toast.show(context, e.message);
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not add the pictures ($e). Try again.');
    }
  }

  void _remove(int index) {
    final names = [...theme.backgrounds]..removeAt(index);
    // Steps count the drawn backdrops first, then the pictures.
    final step = theme.backdrops.length + index, active = theme.activeBackground;
    final next = active > step ? active - 1 : (active == step ? 0 : active);
    onChanged(theme.copyWith(backgrounds: names, activeBackground: next));
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = theme.style.backdrop;
    final muted = AppColorsTheme.of(context).muted;
    final count = theme.backgrounds.length;
    void setBackdrop(BackdropStyle b) => onChanged(theme.copyWith(style: theme.style.copyWith(backdrop: b)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Background pictures'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            count == 0
                ? 'Pictures that show behind the terminal. Next background moves through them in order.'
                : '$count ${count == 1 ? 'picture' : 'pictures'}. Tap one to show it now.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
        if (count > 0)
          SizedBox(
            height: _PictureThumb.height + 16,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _PictureThumb(
                themeId: theme.id,
                name: theme.backgrounds[i],
                label: 'Picture ${i + 1} of $count',
                showing: theme.currentSlide == PictureSlide(theme.backgrounds[i]),
                onShow: () => onChanged(theme.copyWith(activeBackground: theme.backdrops.length + i)),
                onRemove: () => _remove(i),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(onPressed: () => _add(context), icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add pictures')),
          ),
        ),
        if (count > 0 || theme.backdrops.isNotEmpty) ...[
          StyleSlider(
            title: 'Dim the backgrounds',
            value: backdrop.dim,
            max: BackdropStyle.maxDim,
            divisions: 9,
            valueLabel: '${(backdrop.dim * 100).round()} %',
            onChanged: (v) => setBackdrop(backdrop.copyWith(dim: v)),
          ),
          StyleSlider(
            title: 'Blur the backgrounds',
            value: backdrop.blur,
            max: BackdropStyle.maxBlur,
            divisions: 20,
            valueLabel: backdrop.blur == 0 ? 'Off' : '${backdrop.blur.round()}',
            onChanged: (v) => setBackdrop(backdrop.copyWith(blur: v)),
          ),
          SwitchListTile(
            title: const Text('Behind the app\'s screens too'),
            subtitle: const Text('Hosts, Sessions and the other main screens, dimmed more so text stays readable'),
            value: backdrop.onScreens,
            onChanged: (v) => setBackdrop(backdrop.copyWith(onScreens: v)),
          ),
        ],
      ],
    );
  }
}

/// One picture: tap to show it now, with a button to remove it.
class _PictureThumb extends StatelessWidget {
  const _PictureThumb({
    required this.themeId,
    required this.name,
    required this.label,
    required this.showing,
    required this.onShow,
    required this.onRemove,
  });

  final String themeId;
  final String name;
  final String label;
  final bool showing;
  final VoidCallback onShow;
  final VoidCallback onRemove;

  static const height = 88.0;
  static const width = 136.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final radius = BorderRadius.circular(AppStyleTheme.of(context).shapes.field);
    return Semantics(
      label: '$label${showing ? ', showing now' : ''}',
      selected: showing,
      button: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: onShow,
              borderRadius: radius,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.raised,
                  borderRadius: radius,
                  border: Border.all(color: showing ? colors.accent : colors.outline, width: showing ? 3 : 1),
                ),
                child: ExcludeSemantics(child: _ThumbImage(themeId: themeId, name: name)),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Remove ${label.toLowerCase()}',
                style: IconButton.styleFrom(backgroundColor: colors.surface.withValues(alpha: 0.85)),
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picture itself, or a plain box while it loads or when it is gone.
class _ThumbImage extends StatefulWidget {
  const _ThumbImage({required this.themeId, required this.name});

  final String themeId;
  final String name;

  @override
  State<_ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends State<_ThumbImage> {
  /// Looked up once, so redraws do not flicker.
  late Future<File?> _file = ThemeBackgrounds.fileFor(widget.themeId, widget.name);

  @override
  void didUpdateWidget(_ThumbImage old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name || old.themeId != widget.themeId) _file = ThemeBackgrounds.fileFor(widget.themeId, widget.name);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
        future: _file,
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file == null) return Icon(Icons.image_outlined, color: AppColorsTheme.of(context).muted);
          return Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: 272,
            errorBuilder: (context, _, _) => Icon(Icons.broken_image_outlined, color: AppColorsTheme.of(context).muted),
          );
        },
      );
}
