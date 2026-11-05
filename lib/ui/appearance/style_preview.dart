import 'package:flutter/material.dart';

import '../../app/app_icons.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';

/// A small fake app drawn in a theme's colours and style: a card, two
/// buttons, a strip of terminal and the navigation. Used at the top of the
/// style controls so every change shows at once.
///
/// It is drawn at one fixed size and scaled to the width it gets, so it
/// never overflows at any text size or density.
class StylePreview extends StatelessWidget {
  const StylePreview({super.key, required this.theme});

  final ThemeSpec theme;

  static const _size = Size(320, 232);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Preview of the ${theme.name} style',
      image: true,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: AspectRatio(
            aspectRatio: _size.width / _size.height,
            child: FittedBox(
              child: SizedBox.fromSize(
                size: _size,
                child: MediaQuery.withNoTextScaling(
                  child: Theme(data: AppTheme.build(theme), child: _MiniApp(theme: theme)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame: content plus navigation in the chosen place.
class _MiniApp extends StatelessWidget {
  const _MiniApp({required this.theme});

  final ThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final nav = theme.style.nav;
    final content = _MiniContent(theme: theme);
    final Widget body = switch (nav) {
      NavStyle.rail => Row(children: [const _MiniRail(), Expanded(child: content)]),
      NavStyle.floating => Stack(
          children: [
            Positioned.fill(child: content),
            const Positioned(left: 32, right: 32, bottom: 8, child: _MiniBar(labels: false, floating: true)),
          ],
        ),
      _ => Column(children: [Expanded(child: content), _MiniBar(labels: nav == NavStyle.labelled, floating: false)]),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(look.shapes.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.outline),
          borderRadius: BorderRadius.circular(look.shapes.card),
        ),
        child: Material(type: MaterialType.transparency, child: body),
      ),
    );
  }
}

/// A host card, two buttons and a strip of terminal.
class _MiniContent extends StatelessWidget {
  const _MiniContent({required this.theme});

  final ThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final text = Theme.of(context).textTheme;
    const buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: WidgetStatePropertyAll(Size(0, 32)),
    );
    return Stack(
      children: [
        // Something behind the card, so a see-through style shows.
        if (look.surfaces.isGlass)
          Positioned(
            right: 24,
            top: 24,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accent.withValues(alpha: 0.45)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Hosts', style: text.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.hosts, color: colors.muted, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('web-1', maxLines: 1, style: text.bodyMedium),
                            Text('deploy@10.0.0.4', maxLines: 1, style: text.bodySmall?.copyWith(color: colors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(style: buttonStyle, onPressed: () {}, child: const Text('Connect')),
                  const SizedBox(width: 8),
                  OutlinedButton(style: buttonStyle, onPressed: () {}, child: const Text('Edit')),
                ],
              ),
              const SizedBox(height: 8),
              // Takes what is left; at large sizes the end is cut off.
              Expanded(child: _MiniTerminal(theme: theme)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two lines of terminal with the style's padding.
class _MiniTerminal extends StatelessWidget {
  const _MiniTerminal({required this.theme});

  final ThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    final look = AppStyleTheme.of(context);
    final style = TextStyle(fontFamily: TerminalFonts.jetbrains.family, fontSize: 11, height: 1.25, color: Color(theme.foreground));
    return ClipRRect(
      borderRadius: BorderRadius.circular(look.shapes.field),
      child: Container(
        color: Color.lerp(Color(theme.background), Colors.black, theme.isDark ? 0.3 : 0.04),
        alignment: Alignment.topLeft,
        padding: EdgeInsets.all(theme.style.terminal.padding),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: 'user@host', style: style.copyWith(color: Color(theme.ansi[2]))),
            TextSpan(text: ' ~ ', style: style.copyWith(color: Color(theme.ansi[4]))),
            TextSpan(text: '\$ ls\ndocs  run.sh', style: style),
          ]),
          maxLines: 2,
          softWrap: false,
        ),
      ),
    );
  }
}

/// The mini bottom bar, flush or floating.
class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.labels, required this.floating});

  final bool labels;
  final bool floating;

  static const _icons = [AppIcons.hosts, AppIcons.sessions, AppIcons.snippets, AppIcons.settings];
  static const _names = ['Hosts', 'Sessions', 'Snippets', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        for (var i = 0; i < _icons.length; i++)
          Expanded(child: _MiniNavItem(icon: _icons[i], label: labels ? _names[i] : null, selected: i == 0)),
      ],
    );
    if (!floating) {
      return Material(
        color: look.surfaces.bar,
        elevation: look.surfaces.elevation,
        shadowColor: look.surfaces.shadow,
        child: SizedBox(height: labels ? 48 : 40, child: row),
      );
    }
    return Material(
      color: look.surfaces.bar,
      elevation: look.surfaces.style == SurfaceStyle.flat ? 0 : 3,
      shadowColor: look.surfaces.shadow,
      shape: look.shapes.border(look.shapes.pill, BorderSide(color: colors.outline)),
      child: SizedBox(height: 40, child: row),
    );
  }
}

/// The mini side rail.
class _MiniRail extends StatelessWidget {
  const _MiniRail();

  @override
  Widget build(BuildContext context) {
    final look = AppStyleTheme.of(context);
    return Material(
      color: look.surfaces.bar,
      child: const SizedBox(
        width: 48,
        child: Column(
          children: [
            SizedBox(height: 8),
            _MiniNavItem(icon: AppIcons.hosts, selected: true),
            _MiniNavItem(icon: AppIcons.sessions, selected: false),
            _MiniNavItem(icon: AppIcons.snippets, selected: false),
            _MiniNavItem(icon: AppIcons.settings, selected: false),
          ],
        ),
      ),
    );
  }
}

/// One mini navigation item; the chosen one sits on an accent pill.
class _MiniNavItem extends StatelessWidget {
  const _MiniNavItem({required this.icon, required this.selected, this.label});

  final AppIconPair icon;
  final bool selected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final glyph = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected ? colors.accent.withValues(alpha: 0.2) : null,
        borderRadius: BorderRadius.circular(StyleShapes.stadium),
      ),
      child: AppIcon(icon, selected: selected, size: 18, color: selected ? colors.accent : colors.muted),
    );
    if (label == null) return glyph;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        Text(label!, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: selected ? colors.text : colors.muted)),
      ],
    );
  }
}
