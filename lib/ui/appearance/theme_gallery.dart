import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../app/theme_spec.dart';
import 'theme_actions.dart';
import 'theme_preview.dart';

/// A grid of theme cards. Phones get two columns; wider screens get more.
class ThemeGridSliver extends StatelessWidget {
  const ThemeGridSliver({super.key, required this.themes, required this.activeId});

  final List<ThemeSpec> themes;
  final String activeId;

  /// Cards grow up to this width before another column is added.
  static const _maxCardWidth = 220.0;
  static const _gap = 12.0;

  /// Height of the preview as a share of the card's width.
  static const _previewRatio = 0.625;

  @override
  Widget build(BuildContext context) {
    // The name and credit lines grow with the user's text size, so the
    // card's footer is measured from it.
    final scaler = MediaQuery.textScalerOf(context);
    // The menu button needs a full 48 dp, plus 4 dp above and below.
    final footer = math.max(48.0, scaler.scale(14) * 1.45 + scaler.scale(12) * 1.4) + 8;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final columns = math.max(2, ((width + _gap) / (_maxCardWidth + _gap)).ceil());
          final cardWidth = (width - _gap * (columns - 1)) / columns;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
              mainAxisExtent: cardWidth * _previewRatio + footer,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ThemeCard(theme: themes[i], active: themes[i].id == activeId, footerHeight: footer),
              childCount: themes.length,
            ),
          );
        },
      ),
    );
  }
}

/// One theme in the gallery: a preview, its name and credit, a check mark
/// when it is in use, and a menu of actions. Tapping it uses the theme.
class ThemeCard extends StatelessWidget {
  const ThemeCard({super.key, required this.theme, required this.active, required this.footerHeight});

  final ThemeSpec theme;
  final bool active;
  final double footerHeight;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final settings = AppScope.watch(context).settings;
    // Read out as one item, for example "Tokyo Night theme, selected";
    // the check mark and accent border show the same thing to the eye.
    return Semantics(
      container: true,
      button: true,
      label: '${theme.name} theme${active ? ', selected' : ''}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          // Each card shows its theme's own corners.
          borderRadius: BorderRadius.circular(StyleShapes.of(theme.style.shape).card),
          side: BorderSide(color: active ? colors.accent : colors.outline, width: active ? 2 : 1),
        ),
        child: InkWell(
          onTap: () => ThemeActions(context).use(theme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // Drawn once per card; the gallery scrolls over a stored layer.
                child: RepaintBoundary(
                  child: ThemePreview(
                    theme: theme,
                    fontFamily: TerminalFonts.byId(settings, settings.terminalFontId).family,
                    cursorStyle: settings.cursorStyle,
                    backdrop: theme.backdrops.firstOrNull,
                  ),
                ),
              ),
              SizedBox(height: footerHeight, child: _CardFooter(theme: theme, active: active)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name, credit, the in-use check mark and the actions menu.
class _CardFooter extends StatelessWidget {
  const _CardFooter({required this.theme, required this.active});

  final ThemeSpec theme;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final credit = theme.credit ?? (theme.isDark ? 'Dark' : 'Light');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
      child: Row(
        children: [
          Expanded(
            // The card's own label already says this to screen readers.
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(credit, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: colors.muted)),
                ],
              ),
            ),
          ),
          if (active) Icon(Icons.check_circle, size: 20, color: colors.accent),
          _ThemeMenu(theme: theme),
        ],
      ),
    );
  }
}

enum _ThemeAction { edit, editCopy, editText, duplicate, export, delete }

/// The card's "more" menu. Built-in themes cannot change, so they offer
/// a copy to edit instead of Edit and Delete.
class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.theme});

  final ThemeSpec theme;

  void _run(BuildContext context, _ThemeAction action) {
    final actions = ThemeActions(context);
    switch (action) {
      case _ThemeAction.edit:
        actions.edit(theme);
      case _ThemeAction.editCopy:
        actions.editCopy(theme);
      case _ThemeAction.editText:
        actions.editAsText(theme);
      case _ThemeAction.duplicate:
        actions.duplicate(theme);
      case _ThemeAction.export:
        actions.export(theme);
      case _ThemeAction.delete:
        actions.delete(theme);
    }
  }

  @override
  Widget build(BuildContext context) {
    final danger = AppColorsTheme.of(context).danger;
    return PopupMenuButton<_ThemeAction>(
      tooltip: 'Actions for ${theme.name}',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => _run(context, action),
      itemBuilder: (_) => [
        if (theme.builtIn)
          const PopupMenuItem(value: _ThemeAction.editCopy, child: _MenuLabel(Icons.edit_outlined, 'Edit a copy'))
        else ...[
          const PopupMenuItem(value: _ThemeAction.edit, child: _MenuLabel(Icons.edit_outlined, 'Edit')),
          const PopupMenuItem(value: _ThemeAction.duplicate, child: _MenuLabel(Icons.copy_outlined, 'Duplicate')),
        ],
        const PopupMenuItem(value: _ThemeAction.editText, child: _MenuLabel(Icons.data_object, 'Edit as text')),
        const PopupMenuItem(value: _ThemeAction.export, child: _MenuLabel(Icons.ios_share, 'Export')),
        if (!theme.builtIn)
          PopupMenuItem(value: _ThemeAction.delete, child: _MenuLabel(Icons.delete_outline, 'Delete', color: danger)),
      ],
    );
  }
}

/// One line in the card menu: an icon and a word.
class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.icon, this.label, {this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color)),
        ],
      );
}
