import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/backdrops/backdrop_images.dart';
import 'package:multiplex/app/backdrops/backdrop_painter.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_slides.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/app/theme_style.dart';
import 'package:multiplex/app/themes/dark.dart';
import 'package:multiplex/app/themes/light.dart';
import 'package:multiplex/app/themes/originals.dart';
import 'package:multiplex/data/app_settings.dart';

void main() {
  group('catalogue', () {
    test('about two dozen themes, each with 16 colours, its own id and at least two backdrops', () {
      expect(BuiltInThemes.all.length, greaterThanOrEqualTo(24));
      final ids = <String>{};
      for (final theme in BuiltInThemes.all) {
        expect(theme.ansi, hasLength(16), reason: theme.name);
        expect(ids.add(theme.id), isTrue, reason: 'duplicate id ${theme.id}');
        expect(theme.builtIn, isTrue, reason: theme.name);
        expect(theme.backdrops.length, greaterThanOrEqualTo(2), reason: theme.name);
        expect(theme.credit, isNotNull, reason: theme.name);
      }
    });

    test('every theme has a full look of its own; the default keeps the original one', () {
      final looks = <ThemeStyle, String>{};
      for (final theme in BuiltInThemes.all) {
        final other = looks[theme.style];
        expect(other, isNull, reason: '${theme.name} looks the same as $other');
        looks[theme.style] = theme.name;
      }
      expect(BuiltInThemes.matteBlack.style, const ThemeStyle());
      // The default starts on the plain colour, the look Multiplex always had.
      expect(BuiltInThemes.matteBlack.currentSlide, isNull);
    });

    test('gallery order: originals, then dark open schemes, then light ones', () {
      expect(BuiltInThemes.all, [...OriginalThemes.all, ...DarkThemes.all, ...LightThemes.all]);
      expect(BuiltInThemes.all.first, BuiltInThemes.matteBlack);
      // Multiplex's own looks, each on a real scheme it credits.
      for (final t in OriginalThemes.all) {
        expect(t.credit, isNot('Multiplex'), reason: t.name);
        expect(t.credit, contains('MIT'), reason: t.name);
      }
      for (final t in DarkThemes.all) {
        expect(t.isDark, isTrue, reason: t.name);
      }
      for (final t in LightThemes.all) {
        expect(t.isDark, isFalse, reason: t.name);
      }
      for (final name in ['Matte Black', 'Hackerman', 'Ristretto', 'Vesper', 'Flexoki Light', 'Rosé Pine Dawn']) {
        expect(OriginalThemes.all.map((t) => t.name), contains(name));
      }
    });

    test('open schemes keep their published colours', () {
      // Spot checks against the alacritty-theme files they were read from.
      expect(BuiltInThemes.dracula.background, 0xFF282A36);
      expect(BuiltInThemes.dracula.ansi[12], 0xFFCAA9FA);
      expect(BuiltInThemes.solarizedDark.background, 0xFF002B36);
      expect(BuiltInThemes.solarizedLight.foreground, 0xFF586E75);
      expect(BuiltInThemes.oneDark.ansi[4], 0xFF61AFEF);
      expect(BuiltInThemes.gruvboxLight.background, 0xFFFBF1C7);
      expect(BuiltInThemes.ayuDark.ansi[11], 0xFFFFB454);
      expect(BuiltInThemes.ayuLight.background, 0xFFFCFCFC);
      expect(BuiltInThemes.nightOwl.selection, 0xFF0D486E);
      // And the ones under Multiplex's own looks (Omarchy and alacritty-theme).
      expect(BuiltInThemes.matteBlack.background, 0xFF121212);
      expect(BuiltInThemes.matteBlack.accent, 0xFFE68E0D);
      expect(BuiltInThemes.ristretto.ansi[1], 0xFFFD6883);
      expect(BuiltInThemes.hackerman.accent, 0xFF82FB9C);
      expect(BuiltInThemes.flexokiLight.background, 0xFFFFFCF0);
      expect(BuiltInThemes.vesper.ansi[11], 0xFFFFC799);
    });

    test('app text and muted text read at 4.5:1 on every theme', () {
      double ratio(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
      }

      for (final theme in BuiltInThemes.all) {
        final c = AppColors.derive(theme);
        expect(ratio(c.text, c.surface), greaterThanOrEqualTo(4.5), reason: theme.name);
        expect(ratio(c.muted, c.surface), greaterThanOrEqualTo(4.5), reason: theme.name);
      }
    });
  });

  group('backdrops', () {
    const phone = Size(390, 844), tablet = Size(1024, 1366);

    test('every pattern draws at phone and tablet sizes, and differs from a plain fill', () async {
      for (final pattern in BackdropPattern.values) {
        for (final (size, ratio) in [(phone, 3.0), (tablet, 2.0)]) {
          final colors = BackdropColors.of(BuiltInThemes.tokyoNight);
          final image = BackdropImages.draw(pattern, colors, size, ratio);
          expect(image.width, (size.width * ratio).round(), reason: '$pattern');
          expect(image.height, (size.height * ratio).round(), reason: '$pattern');
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final first = bytes.getUint32(0);
          var differs = false;
          for (var i = 0; i < bytes.lengthInBytes && !differs; i += 4 * 97) {
            differs = bytes.getUint32(i) != first;
          }
          expect(differs, isTrue, reason: '$pattern at $size drew nothing');
          image.dispose();
        }
      }
    });

    test('every built-in backdrop draws in its own theme\'s colours', () {
      for (final theme in BuiltInThemes.all) {
        for (final pattern in theme.backdrops) {
          final image = BackdropImages.draw(pattern, BackdropColors.of(theme), phone, 1);
          expect(image.width, phone.width.round(), reason: '${theme.name} $pattern');
          image.dispose();
        }
      }
    });

    test('the cache hands out separate handles and reuses one drawing', () {
      final colors = BackdropColors.of(BuiltInThemes.nord);
      final a = BackdropImages.of(BackdropPattern.dots, colors, phone, 2);
      final b = BackdropImages.of(BackdropPattern.dots, colors, const Size(392, 840), 2);
      expect(a.isCloneOf(b), isTrue);
      a.dispose();
      // Disposing one handle leaves the other usable.
      expect(b.width, greaterThan(0));
      b.dispose();
    });

    test('a theme always gets the same drawing', () {
      expect(BackdropColors.of(BuiltInThemes.synthwave84), BackdropColors.of(BuiltInThemes.synthwave84));
      expect(BackdropColors.of(BuiltInThemes.synthwave84).seed, isNot(BackdropColors.of(BuiltInThemes.oxocarbon).seed));
    });
  });

  group('next background', () {
    test('steps run through the backdrops, then the pictures, then the plain colour', () {
      final theme = BuiltInThemes.hackerman.copyWith(id: 'mine', backgrounds: ['me.png']);
      expect(theme.slideCount, theme.backdrops.length + 2);
      expect(theme.slideAt(0), PatternSlide(theme.backdrops.first));
      expect(theme.slideAt(theme.backdrops.length), const PictureSlide('me.png'));
      expect(theme.slideAt(theme.backdrops.length + 1), isNull);
      expect(theme.slideAt(theme.slideCount), PatternSlide(theme.backdrops.first));
    });

    test('a built-in theme\'s choice is kept in the settings', () {
      const settings = AppSettings(backdropPicks: {'synthwave-84': 1});
      expect(ActiveSlide.of(BuiltInThemes.synthwave84, settings), PatternSlide(BuiltInThemes.synthwave84.backdrops[1]));
      expect(ActiveSlide.index(BuiltInThemes.nord, settings), 0);
      final back = AppSettings.fromJson(settings.toJson());
      expect(back.backdropPicks, {'synthwave-84': 1});
      // A custom theme keeps its own step, whatever the settings say.
      final mine = BuiltInThemes.synthwave84.copyWith(id: 'neon-copy', activeBackground: 2);
      expect(ActiveSlide.index(mine, const AppSettings(backdropPicks: {'neon-copy': 0})), 2);
    });
  });
}
