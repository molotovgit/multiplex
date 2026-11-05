import 'package:flutter/material.dart';

import '../../app/app_icons.dart';
import '../../app/terminal_backgrounds.dart';
import '../../app/theme.dart';
import '../../app/theme_style.dart';
import '../common/widgets.dart';
import 'style_controls.dart';
import 'style_section.dart';

/// The terminal part of a style: padding, a background picture with its
/// dimming and blur, and the tab strip.
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
          BackgroundPicturePicker(
            fileName: style.backgroundImage,
            onChanged: (name) => onChanged(style.copyWith(backgroundImage: () => name)),
          ),
          if (style.hasImage) ...[
            StyleSlider(
              title: 'Dim the picture',
              value: style.dim,
              max: TerminalStyle.maxDim,
              divisions: 9,
              valueLabel: '${(style.dim * 100).round()} %',
              onChanged: (v) => onChanged(style.copyWith(dim: v)),
            ),
            StyleSlider(
              title: 'Blur the picture',
              value: style.blur,
              max: TerminalStyle.maxBlur,
              divisions: 20,
              valueLabel: style.blur == 0 ? 'Off' : '${style.blur.round()}',
              onChanged: (v) => onChanged(style.copyWith(blur: v)),
            ),
          ],
          SwitchListTile(
            title: const Text('Terminal tabs'),
            subtitle: const Text('Shows the connection\'s terminals in a strip above the text'),
            value: style.showTabs,
            onChanged: (v) => onChanged(style.copyWith(showTabs: v)),
          ),
        ],
      );
}

/// Choose or remove the picture behind the terminal. The picture is
/// copied into the app, so moving or deleting the original does not
/// matter. Exported themes carry only its name.
class BackgroundPicturePicker extends StatelessWidget {
  const BackgroundPicturePicker({super.key, required this.fileName, required this.onChanged});

  final String? fileName;
  final ValueChanged<String?> onChanged;

  Future<void> _choose(BuildContext context) async {
    try {
      final name = await TerminalBackgrounds.pick();
      if (name != null) onChanged(name);
    } on BackgroundFileException catch (e) {
      if (context.mounted) Toast.show(context, e.message);
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not add the picture ($e). Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColorsTheme.of(context).muted;
    final text = Theme.of(context).textTheme;
    // The buttons sit under the text, so both fit at any text size.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.image, color: muted),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Background picture', style: text.titleSmall),
                    Text(fileName == null ? 'None, the theme\'s colour shows' : 'A picture shows behind the text',
                        style: text.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => _choose(context),
                child: Text(fileName == null ? 'Choose picture' : 'Change picture'),
              ),
              if (fileName != null) OutlinedButton(onPressed: () => onChanged(null), child: const Text('Remove picture')),
            ],
          ),
        ],
      ),
    );
  }
}
