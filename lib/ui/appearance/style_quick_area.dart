import 'package:flutter/material.dart';

import '../../app/app_icons.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';
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
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => ThemeActions(context).edit(theme),
              icon: const AppIcon(AppIcons.style),
              label: const Text('All style options'),
            ),
          ),
        ),
      ],
    );
  }
}
