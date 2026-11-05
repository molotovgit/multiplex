import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/terminal_fonts.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_look.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/app/theme_style.dart';
import 'package:multiplex/ui/keyboard/keyboard_settings.dart';
import 'package:multiplex/ui/keyboard/keyboard_style.dart';
import 'package:multiplex/ui/appearance/theme_export.dart';
import 'package:multiplex/ui/appearance/theme_import.dart';

/// A style with every field away from its default.
abstract final class _Styles {
  static const everything = ThemeStyle(
    shape: CornerShape.square,
    surface: SurfaceStyle.glass,
    density: StyleDensity.compact,
    appFont: 'plex',
    textScale: 1.2,
    nav: NavStyle.rail,
    icons: IconStyle.filled,
    terminal: TerminalStyle(padding: 16, showTabs: true),
    backdrop: BackdropStyle(dim: 0.6, blur: 8, onScreens: true),
    keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 6, labelFont: KeyLabelFont.terminal),
  );
}

void main() {
  group('style model', () {
    test('the defaults are the original look', () {
      const d = ThemeStyle();
      expect(d.shape, CornerShape.rounded);
      expect(d.shape.radius, 14);
      expect(d.surface, SurfaceStyle.outlined);
      expect(d.density, StyleDensity.normal);
      expect(d.appFont, ThemeStyle.systemFont);
      expect(d.textScale, 1.0);
      expect(d.nav, NavStyle.labelled);
      expect(d.icons, IconStyle.outlined);
      expect(d.terminal.padding, 4);
      expect(d.terminal.showTabs, isFalse);
      expect(d.backdrop.onScreens, isFalse);
      expect(d.keys.cap, KeyCapStyle.raised);
      expect(d.keys.gap, 4);
      expect(d.keys.labelFont, KeyLabelFont.app);
      expect(BuiltInThemes.matteBlack.style, d);
    });

    test('every field survives a JSON round trip', () {
      final back = ThemeStyle.fromJson(_Styles.everything.toJson());
      expect(back, _Styles.everything);
      expect(back.copyWith(), _Styles.everything);
      expect(back.copyWith(nav: NavStyle.floating).nav, NavStyle.floating);
    });

    test('missing, broken or odd values fall back or snap to an allowed one', () {
      expect(ThemeStyle.fromJson(null), const ThemeStyle());
      expect(ThemeStyle.fromJson('not a map'), const ThemeStyle());
      final odd = ThemeStyle.fromJson({
        'shape': 'blob',
        'nav': 42,
        'textScale': 3.0,
        'terminal': {'padding': 5},
        'backdrop': {'dim': 7, 'blur': -3},
        'keys': {'gap': 100, 'cap': 'shiny'},
      });
      expect(odd.shape, CornerShape.rounded);
      expect(odd.nav, NavStyle.labelled);
      expect(odd.textScale, 1.2);
      expect(odd.terminal.padding, 4);
      expect(odd.backdrop.dim, BackdropStyle.maxDim);
      expect(odd.backdrop.blur, 0);
      expect(odd.keys.gap, 6);
      expect(odd.keys.cap, KeyCapStyle.raised);
    });

    test('a background picture is only ever a plain file name', () {
      for (final bad in ['../secret.png', 'a/b.png', r'a\b.png', '.hidden', '', 'x' * 200, 42]) {
        expect(SafeFileName.of(bad), isNull, reason: '$bad');
      }
      expect(SafeFileName.of('3f2a-b.jpg'), '3f2a-b.jpg');
    });

    test('a theme keeps its picture list; unsafe names are dropped', () {
      final mine = BuiltInThemes.matteBlack.copyWith(id: 'mine', backgrounds: ['a.jpg', 'b.png', 'c.webp'], backdrops: const [], activeBackground: 2);
      final back = ThemeSpec.fromJson(mine.toJson());
      expect(back.backgrounds, ['a.jpg', 'b.png', 'c.webp']);
      expect(back.currentSlide, const PictureSlide('c.webp'));
      final odd = ThemeSpec.fromJson({...mine.toJson(), 'backgrounds': ['ok.jpg', '../x.jpg', 7], 'activeBackground': 9});
      expect(odd.backgrounds, ['ok.jpg']);
      // Clamped to the last step, the plain colour after the one picture.
      expect(odd.activeBackground, 1);
      expect(odd.currentSlide, isNull);
      expect(BuiltInThemes.matteBlack.copyWith(backdrops: const []).currentSlide, isNull);
      // A new list starts at its first picture.
      expect(back.copyWith(backgrounds: ['z.png']).activeBackground, 0);
    });

    test('a theme saved before styles existed loads with the default style', () {
      final old = BuiltInThemes.nord.toJson()..remove('style');
      expect(ThemeSpec.fromJson(old).style, const ThemeStyle());
    });

    test('themes carry their style through JSON, copies and export and import', () {
      final mine = BuiltInThemes.matteBlack.copyWith(id: 'mine', name: 'Mine', style: _Styles.everything);
      expect(ThemeSpec.fromJson(mine.toJson()).style, _Styles.everything);
      expect(mine.copyWith(name: 'Other').style, _Styles.everything);
      final imported = ThemeImporter().read(ThemeExport.json(mine.copyWith(backgrounds: ['a.jpg'])));
      expect(imported.style, _Styles.everything);
      expect(imported.id, isNot('mine'));
      // The pictures do not travel in the text, so their names do not either.
      expect(imported.backgrounds, isEmpty);
    });

    test('several built-in themes have a look of their own', () {
      final looks = {for (final t in BuiltInThemes.all) t.style};
      expect(looks.length, greaterThanOrEqualTo(5));
      expect(BuiltInThemes.githubHighContrast.style.shape, CornerShape.square);
      expect(BuiltInThemes.githubHighContrast.style.surface, SurfaceStyle.flat);
      expect(BuiltInThemes.catppuccinMocha.style.shape, CornerShape.round);
      expect(BuiltInThemes.catppuccinMocha.style.surface, SurfaceStyle.raised);
      expect(BuiltInThemes.tokyoNight.style.nav, NavStyle.floating);
      expect(BuiltInThemes.nord.style.density, StyleDensity.comfortable);
    });
  });

  group('material theme', () {
    ThemeData build(ThemeStyle style) => AppTheme.build(BuiltInThemes.matteBlack.copyWith(style: style));
    RoundedRectangleBorder cardShape(ThemeData t) => t.cardTheme.shape! as RoundedRectangleBorder;

    test('the default style keeps the original card, field and button shapes', () {
      final t = build(const ThemeStyle());
      expect(cardShape(t).borderRadius, BorderRadius.circular(14));
      expect(cardShape(t).side.color, AppColors.derive(BuiltInThemes.matteBlack).outline);
      expect((t.inputDecorationTheme.border! as OutlineInputBorder).borderRadius, BorderRadius.circular(10));
      // Normal density leaves Material's own choice for the platform.
      expect(t.visualDensity, ThemeData(useMaterial3: true).visualDensity);
      expect(t.extension<AppStyleTheme>()!.style, const ThemeStyle());
    });

    test('corners follow the shape on cards, fields, buttons, sheets and dialogs', () {
      final square = build(const ThemeStyle(shape: CornerShape.square));
      expect(cardShape(square).borderRadius, BorderRadius.zero);
      expect((square.inputDecorationTheme.border! as OutlineInputBorder).borderRadius, BorderRadius.zero);
      final button = square.filledButtonTheme.style!.shape!.resolve({})! as RoundedRectangleBorder;
      expect(button.borderRadius, BorderRadius.zero);
      expect((square.dialogTheme.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.zero);
      final round = build(const ThemeStyle(shape: CornerShape.round));
      expect(cardShape(round).borderRadius, BorderRadius.circular(24));
      expect((round.bottomSheetTheme.shape! as RoundedRectangleBorder).borderRadius, const BorderRadius.vertical(top: Radius.circular(32)));
    });

    test('surfaces: flat has no border, raised a tinted shadow, glass is see-through', () {
      expect(cardShape(build(const ThemeStyle(surface: SurfaceStyle.flat))).side, BorderSide.none);
      final raised = build(const ThemeStyle(surface: SurfaceStyle.raised));
      expect(cardShape(raised).side, BorderSide.none);
      expect(raised.cardTheme.elevation, greaterThan(0));
      expect(raised.cardTheme.shadowColor, isNot(Colors.black));
      final glass = build(const ThemeStyle(surface: SurfaceStyle.glass));
      expect(glass.cardTheme.color!.a, lessThan(1));
    });

    test('density, app font and text size reach the Material theme', () {
      expect(build(const ThemeStyle(density: StyleDensity.compact)).visualDensity, VisualDensity.compact);
      expect(build(const ThemeStyle(density: StyleDensity.comfortable)).listTileTheme.minVerticalPadding, 12);
      final normal = Typography.englishLike2021.bodyMedium!.fontSize!;
      final big = build(const ThemeStyle(textScale: 1.2, appFont: 'jetbrains')).textTheme;
      expect(big.bodyMedium!.fontSize, closeTo(normal * 1.2, 0.01));
      expect(big.bodyMedium!.fontFamily, TerminalFonts.jetbrains.family);
      expect(AppFonts.family(ThemeStyle.systemFont), isNull);
      expect(AppFonts.family('my-font'), 'custom-my-font');
    });

    test('keyboard keys follow the corner shape and gap; square keys stay square', () {
      const screen = Size(400, 800);
      const keyboard = KeyboardSettings();
      final rounded = KeyboardMetrics.resolve(keyboard, screen);
      final square = KeyboardMetrics.resolve(keyboard, screen, style: const ThemeStyle(shape: CornerShape.square));
      final round = KeyboardMetrics.resolve(keyboard, screen, style: const ThemeStyle(shape: CornerShape.round));
      expect(square.radius, 0);
      expect(round.radius, greaterThan(rounded.radius));
      expect(rounded.gapX, KeyboardMetrics.defaultGapX);
      expect(rounded.gapY, KeyboardMetrics.defaultGapY);
      final wide = KeyboardMetrics.resolve(keyboard, screen, style: const ThemeStyle(keys: KeysStyle(gap: 6, cap: KeyCapStyle.flat)));
      expect(wide.gapY, 6);
      expect(wide.cap, KeyCapStyle.flat);
      final forcedSquare = KeyboardMetrics.resolve(const KeyboardSettings(shape: KeyShape.square), screen, style: const ThemeStyle(shape: CornerShape.round));
      expect(forcedSquare.radius, lessThan(round.radius));
    });
  });
}
