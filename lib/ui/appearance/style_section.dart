import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme_look.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_style.dart';
import '../common/widgets.dart';
import 'style_controls.dart';
import 'style_preview.dart';
import 'style_terminal_parts.dart';

/// Option lists for the style controls, in the order they are shown.
abstract final class StyleOptions {
  static final shapes = [for (final s in CornerShape.values) StyleOption(s, s.label)];
  static final surfaces = [for (final s in SurfaceStyle.values) StyleOption(s, s.label)];
  static final densities = [for (final d in StyleDensity.values) StyleOption(d, d.label)];
  static final navs = [for (final n in NavStyle.values) StyleOption(n, n.label)];
  static final icons = [for (final i in IconStyle.values) StyleOption(i, i.label)];
  static final textScales = [for (final t in ThemeStyle.textScales) StyleOption(t, '${(t * 100).round()} %')];
  static const paddings = [StyleOption(0.0, 'None'), StyleOption(4.0, 'Small'), StyleOption(8.0, 'Medium'), StyleOption(16.0, 'Large')];
  static final caps = [for (final c in KeyCapStyle.values) StyleOption(c, c.label)];
  static const gaps = [StyleOption(2.0, 'Narrow'), StyleOption(4.0, 'Normal'), StyleOption(6.0, 'Wide')];
  static final labelFonts = [for (final f in KeyLabelFont.values) StyleOption(f, f.label)];

  /// "Raised: a soft shadow", for the chosen option.
  static String surfaceHint(SurfaceStyle s) => '${s.label}: ${s.description[0].toLowerCase()}${s.description.substring(1)}.';
  static String navHint(NavStyle n) => '${n.label}: ${n.description[0].toLowerCase()}${n.description.substring(1)}.';
}

/// The main look controls: corners, surfaces, navigation and icons. Shared
/// by the theme editor and the quick style area on the Appearance screen.
class StyleBasics extends StatelessWidget {
  const StyleBasics({super.key, required this.style, required this.onChanged});

  final ThemeStyle style;
  final ValueChanged<ThemeStyle> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StyleChoice(
            title: 'Corners',
            options: StyleOptions.shapes,
            selected: style.shape,
            onChanged: (v) => onChanged(style.copyWith(shape: v)),
          ),
          StyleChoice(
            title: 'Surfaces',
            description: StyleOptions.surfaceHint(style.surface),
            options: StyleOptions.surfaces,
            selected: style.surface,
            onChanged: (v) => onChanged(style.copyWith(surface: v)),
          ),
          StyleChoice(
            title: 'Navigation',
            description: StyleOptions.navHint(style.nav),
            options: StyleOptions.navs,
            selected: style.nav,
            onChanged: (v) => onChanged(style.copyWith(nav: v)),
          ),
          StyleChoice(
            title: 'Icons',
            options: StyleOptions.icons,
            selected: style.icons,
            onChanged: (v) => onChanged(style.copyWith(icons: v)),
          ),
        ],
      );
}

/// Every style control, with a live preview on top. Used in the theme
/// editor: changes go to the draft and are saved with the theme.
class StyleSection extends StatelessWidget {
  const StyleSection({super.key, required this.theme, required this.onChanged});

  /// The draft theme; its colours colour the preview.
  final ThemeSpec theme;
  final ValueChanged<ThemeStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = theme.style;
    final settings = AppScope.watch(context).settings;
    final fonts = AppFonts.choices(settings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Style'),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: StylePreview(theme: theme)),
        StyleBasics(style: style, onChanged: onChanged),
        StyleChoice(
          title: 'Density',
          description: 'How much room rows and controls take',
          options: StyleOptions.densities,
          selected: style.density,
          onChanged: (v) => onChanged(style.copyWith(density: v)),
        ),
        const SectionHeader('App text'),
        StyleChoice(
          title: 'Font',
          options: [for (final f in fonts) StyleOption(f.id, f.name)],
          // A font removed from this device shows as the system font.
          selected: fonts.any((f) => f.id == style.appFont) ? style.appFont : ThemeStyle.systemFont,
          onChanged: (v) => onChanged(style.copyWith(appFont: v)),
        ),
        StyleChoice(
          title: 'Text size',
          description: 'On top of the text size set for the phone',
          options: StyleOptions.textScales,
          selected: style.textScale,
          onChanged: (v) => onChanged(style.copyWith(textScale: v)),
        ),
        TerminalStyleControls(style: style.terminal, onChanged: (t) => onChanged(style.copyWith(terminal: t))),
        const SectionHeader('Keyboard'),
        StyleChoice(
          title: 'Keys',
          options: StyleOptions.caps,
          selected: style.keys.cap,
          onChanged: (v) => onChanged(style.copyWith(keys: style.keys.copyWith(cap: v))),
        ),
        StyleChoice(
          title: 'Space between keys',
          options: StyleOptions.gaps,
          selected: style.keys.gap,
          onChanged: (v) => onChanged(style.copyWith(keys: style.keys.copyWith(gap: v))),
        ),
        StyleChoice(
          title: 'Key labels',
          options: StyleOptions.labelFonts,
          selected: style.keys.labelFont,
          onChanged: (v) => onChanged(style.copyWith(keys: style.keys.copyWith(labelFont: v))),
        ),
      ],
    );
  }
}
