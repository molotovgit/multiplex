import '../../app/app_icons.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../app/theme_spec.dart';
import '../common/widgets.dart';
import 'style_quick_area.dart';
import 'terminal_text_section.dart';
import 'theme_actions.dart';
import 'theme_gallery.dart';
import 'theme_import_flow.dart';

/// Themes, style, fonts and cursor. One theme styles the whole app,
/// screens and terminal alike, colours and the look of the elements;
/// tapping a theme uses it at once. Users can make their
/// own themes, import them from other terminals and pick the terminal
/// font, size, line height and cursor.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  /// Widest the font and cursor settings get; the gallery uses the full
  /// width and adds columns instead.
  static const _formWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Create theme', onPressed: () => ThemeActions(context).create()),
          IconButton(
            icon: const AppIcon(AppIcons.download),
            tooltip: 'Import theme',
            onPressed: () => ThemeImportFlow(context).start(),
          ),
        ],
      ),
      // Side insets keep the page clear of a notch in landscape.
      body: const SafeArea(top: false, bottom: false, child: _AppearanceBody()),
    );
  }
}

/// The galleries and the terminal text settings, in one scrolling page.
/// Redraws whenever a theme or setting changes.
class _AppearanceBody extends StatelessWidget {
  const _AppearanceBody();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final activeId = store.activeTheme.id;
    final custom = store.customThemes;
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SectionHeader('Built-in')),
        ThemeGridSliver(themes: BuiltInThemes.all, activeId: activeId),
        const SliverToBoxAdapter(child: SectionHeader('Your themes')),
        if (custom.isEmpty) const SliverToBoxAdapter(child: _NoCustomThemes()) else ThemeGridSliver(themes: custom, activeId: activeId),
        const SliverToBoxAdapter(child: _ThemeButtons()),
        const SliverToBoxAdapter(child: _FormWidth(child: StyleQuickArea())),
        const SliverToBoxAdapter(child: _FormWidth(child: TerminalTextSection())),
        // Room at the end so the last controls clear the gesture bar.
        SliverPadding(padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

/// Keeps a form readable on wide screens.
class _FormWidth extends StatelessWidget {
  const _FormWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppearanceScreen._formWidth), child: child),
      );
}

/// What "Your themes" shows before the user has any.
class _NoCustomThemes extends StatelessWidget {
  const _NoCustomThemes();

  @override
  Widget build(BuildContext context) {
    final muted = AppColorsTheme.of(context).muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        'Themes you create or import show up here. Start from the theme in use, or bring one from Alacritty, Kitty or Ghostty.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
      ),
    );
  }
}

/// "Create theme" and "Import theme", under the user's own themes.
class _ThemeButtons extends StatelessWidget {
  const _ThemeButtons();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => ThemeActions(context).create(),
              icon: const Icon(Icons.add),
              label: const Text('Create theme'),
            ),
            OutlinedButton.icon(
              onPressed: () => ThemeImportFlow(context).start(),
              icon: const AppIcon(AppIcons.download),
              label: const Text('Import theme'),
            ),
          ],
        ),
      );
}
