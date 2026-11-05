import 'package:flutter/material.dart';

import '../../app/app_icons.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_slides.dart';
import '../../data/app_settings.dart';
import '../common/widgets.dart';
import 'style_controls.dart';
import 'style_preview.dart';
import 'style_section.dart';
import 'theme_actions.dart';

/// The main style controls for the theme in use, right on the Appearance
/// screen. Every change is saved and shown at once; a built-in theme is
/// copied first. "All style options" opens the full editor.
class StyleQuickArea extends StatelessWidget {
  const StyleQuickArea({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppScope.watch(context).activeTheme;
    final muted = AppColorsTheme.of(context).muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Style'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            theme.builtIn
                ? 'How the elements of ${theme.name} look. Changing them saves a copy, so the built-in theme stays as it is.'
                : 'How the elements of ${theme.name} look. Changes are saved with the theme.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: StylePreview(theme: theme)),
        StyleBasics(style: theme.style, onChanged: (style) => ThemeActions(context).updateStyle(style)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => ThemeActions(context).edit(theme),
                icon: const AppIcon(AppIcons.style),
                label: const Text('All style options'),
              ),
              OutlinedButton.icon(
                onPressed: () => ThemeActions(context).nextBackground(),
                icon: const AppIcon(AppIcons.image),
                label: Text(
                  theme.slideCount == 0 ? 'Next background' : 'Next background (now: ${BackgroundNames.of(ActiveSlide.of(theme, AppScope.watch(context).settings))})',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How fast theme changes and sheets move. When the phone asks for less
/// motion, motion is off whatever is chosen here, and the setting says so.
class MotionSetting extends StatelessWidget {
  const MotionSetting({super.key});

  static final _options = [for (final m in MotionSpeed.values) StyleOption(m, m.label)];

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Motion'),
        StyleChoice(
          title: 'Animation speed',
          description: reduced
              ? 'Your device asks for less motion, so theme changes and sheets do not move.'
              : 'How theme changes and sheets move',
          options: _options,
          selected: store.settings.motion,
          onChanged: (m) => store.updateSettings(store.settings.copyWith(motion: m)),
        ),
      ],
    );
  }
}
