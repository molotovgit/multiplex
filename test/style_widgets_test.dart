import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/multiplex_app.dart';
import 'package:multiplex/app/theme_backgrounds.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/app/theme_style.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/appearance/appearance_screen.dart';
import 'package:multiplex/ui/appearance/theme_editor_screen.dart';
import 'package:multiplex/ui/home/home_shell.dart';
import 'package:multiplex/ui/keyboard/key_sink.dart';
import 'package:multiplex/ui/keyboard/terminal_keyboard_panel.dart';
import 'package:multiplex/ui/common/theme_backdrop.dart';

/// A keyboard sink that ignores everything.
class _NoSink implements KeySink {
  @override
  void sendText(String text, KeyModifiers mods) {}

  @override
  void sendKey(TerminalKey key, KeyModifiers mods) {}

  @override
  void pasteClipboard() {}
}

/// Opens screens on a fresh store with a theme of a given style.
class _Harness {
  late VaultStore store;
  late SessionManager sessions;

  Future<void> open(WidgetTester tester, {ThemeStyle? style, Widget? home, Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = await VaultStore.open(MemoryBackend());
    sessions = SessionManager(store);
    if (style != null) {
      store.saveTheme(BuiltInThemes.ember.copyWith(id: 'styled', name: 'Styled', style: style));
      store.updateSettings(store.settings.copyWith(themeId: 'styled'));
    }
    await tester.pumpWidget(
      home == null
          ? MultiplexApp(store: store, sessions: sessions)
          : AppScope(
              vault: store,
              manager: sessions,
              child: ListenableBuilder(
                listenable: store,
                builder: (_, _) => MaterialApp(theme: AppTheme.build(store.activeTheme), home: home),
              ),
            ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the store's delayed save run and stops the sessions.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  }
}

void main() {
  group('navigation style', () {
    testWidgets('labelled and icons-only bottom bars', (tester) async {
      final h = _Harness();
      await h.open(tester);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
      expect(find.byType(NavigationRail), findsNothing);
      h.store.saveTheme(h.store.activeTheme.copyWith(id: 'icons', style: const ThemeStyle(nav: NavStyle.iconsOnly)));
      h.store.updateSettings(h.store.settings.copyWith(themeId: 'icons'));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);
      await h.finish(tester);
    });

    testWidgets('the floating bar sits above the content and still navigates', (tester) async {
      final h = _Harness();
      await h.open(tester, style: const ThemeStyle(nav: NavStyle.floating));
      expect(find.byKey(HomeShell.floatingBarKey), findsOneWidget);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody, isTrue);
      final bar = tester.getRect(find.byKey(HomeShell.floatingBarKey));
      expect(bar.left, greaterThanOrEqualTo(16));
      expect(bar.bottom, lessThanOrEqualTo(800 - 12));
      await tester.tap(find.descendant(of: find.byKey(HomeShell.floatingBarKey), matching: find.text('Settings')));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 4);
      await h.finish(tester);
    });

    testWidgets("a page's own button stays above the floating bar", (tester) async {
      final h = _Harness();
      await h.open(tester, style: const ThemeStyle(nav: NavStyle.floating));
      final bar = tester.getRect(find.byKey(HomeShell.floatingBarKey));
      final button = tester.getRect(find.widgetWithText(FloatingActionButton, 'New host'));
      expect(button.bottom, lessThanOrEqualTo(bar.top));
      await h.finish(tester);
    });

    testWidgets("a page's own button stays above a see-through bar", (tester) async {
      final h = _Harness();
      await h.open(tester, style: const ThemeStyle(surface: SurfaceStyle.glass));
      final bar = tester.getRect(find.byType(NavigationBar));
      final button = tester.getRect(find.widgetWithText(FloatingActionButton, 'New host'));
      expect(button.bottom, lessThanOrEqualTo(bar.top));
      await h.finish(tester);
    });

    testWidgets('the side rail is used on phones when chosen', (tester) async {
      final h = _Harness();
      await h.open(tester, style: const ThemeStyle(nav: NavStyle.rail));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      // Icons only on a phone, so the pages keep their width.
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).labelType, NavigationRailLabelType.none);
      expect(tester.getSize(find.byType(NavigationRail)).width, lessThanOrEqualTo(56));
      await h.finish(tester);
    });

    testWidgets('the floating bar keeps its end items clear of its round ends', (tester) async {
      final h = _Harness();
      await h.open(tester, style: const ThemeStyle(nav: NavStyle.floating));
      final bar = tester.getRect(find.byKey(HomeShell.floatingBarKey));
      final items = tester.getRect(find.descendant(of: find.byKey(HomeShell.floatingBarKey), matching: find.byType(NavigationBar)));
      expect(items.left - bar.left, greaterThanOrEqualTo(12));
      expect(bar.right - items.right, greaterThanOrEqualTo(12));
      await h.finish(tester);
    });

    testWidgets('icons switch between outlined and filled', (tester) async {
      final h = _Harness();
      await h.open(tester);
      expect(find.byIcon(Icons.terminal_outlined), findsOneWidget);
      h.store.saveTheme(h.store.activeTheme.copyWith(id: 'filled', style: const ThemeStyle(icons: IconStyle.filled)));
      h.store.updateSettings(h.store.settings.copyWith(themeId: 'filled'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.terminal_outlined), findsNothing);
      expect(find.byIcon(Icons.terminal), findsOneWidget);
      await h.finish(tester);
    });
  });

  group('background picture', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('backgrounds');
      Directory('${root.path}${Platform.pathSeparator}pack').createSync();
      File('${root.path}${Platform.pathSeparator}pack${Platform.pathSeparator}bg.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
      ThemeBackgrounds.rootOverride = root;
    });
    tearDown(() {
      ThemeBackgrounds.rootOverride = null;
      root.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester tester, String? picture, {double dim = 0.4, double blur = 0}) async {
      await tester.pumpWidget(MaterialApp(
        home: ThemeBackdrop(
          theme: BuiltInThemes.ember.copyWith(id: 'pack'),
          slide: picture == null ? null : PictureSlide(picture),
          color: const Color(0xFF101010),
          dim: dim,
          blur: blur,
        ),
      ));
      await tester.pump();
    }

    testWidgets('without a picture only the colour shows', (tester) async {
      await pump(tester, null);
      expect(find.byKey(ThemeBackdrop.dimKey), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a picture is blurred and dimmed with the background colour', (tester) async {
      await pump(tester, 'bg.png', dim: 0.6, blur: 4);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ImageFiltered), findsOneWidget);
      final dim = tester.widget<ColoredBox>(find.byKey(ThemeBackdrop.dimKey));
      expect(dim.color.a, closeTo(0.6, 0.01));
      expect(dim.color.r, closeTo(const Color(0xFF101010).r, 0.01));
    });

    testWidgets('a picture missing on this device falls back to the colour', (tester) async {
      await pump(tester, 'gone.png');
      expect(find.byType(Image), findsNothing);
    });
  });

  group('keyboard keys', () {
    BoxDecoration keyDecoration(WidgetTester tester) =>
        tester.widget<DecoratedBox>(find.ancestor(of: find.text('q'), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
    EdgeInsets keyPadding(WidgetTester tester) =>
        tester.widget<Padding>(find.ancestor(of: find.byType(DecoratedBox).hitTestable().first, matching: find.byType(Padding)).first).padding
            as EdgeInsets;

    Widget panel() => Scaffold(
          body: Column(children: [
            const Expanded(child: SizedBox.expand()),
            TerminalKeyboardPanel.withSink(sink: _NoSink(), onSnippets: () {}, onHide: () {}, onSwitchToSystem: () {}),
          ]),
        );

    testWidgets('raised keys have a shadow and no border', (tester) async {
      final h = _Harness();
      await h.open(tester, home: panel());
      final d = keyDecoration(tester);
      expect(d.boxShadow, isNotEmpty);
      expect(d.border, isNull);
      await h.finish(tester);
    });

    testWidgets('outlined keys have a border, flat keys neither, and the gap is used', (tester) async {
      final h = _Harness();
      await h.open(tester, style: const ThemeStyle(keys: KeysStyle(cap: KeyCapStyle.outlined, gap: 6)), home: panel());
      expect(keyDecoration(tester).border, isNotNull);
      expect(keyDecoration(tester).boxShadow, isNull);
      expect(keyPadding(tester).top, 6);
      h.store.saveTheme(h.store.activeTheme.copyWith(style: const ThemeStyle(keys: KeysStyle(cap: KeyCapStyle.flat))));
      await tester.pumpAndSettle();
      expect(keyDecoration(tester).border, isNull);
      expect(keyDecoration(tester).boxShadow, isNull);
      await h.finish(tester);
    });
  });

  group('editing the style', () {
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
      );
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
    }

    // Not narrowed to the first match until it is built: lists build lazily.
    Finder chip(String label) => find.widgetWithText(ChoiceChip, label);

    testWidgets('changing a built-in theme on the Appearance screen saves a copy', (tester) async {
      final h = _Harness();
      await h.open(tester, home: const AppearanceScreen());
      await scrollTo(tester, chip('Square'));
      await tester.tap(chip('Square').first);
      await tester.pumpAndSettle();
      final copy = h.store.activeTheme;
      expect(copy.builtIn, isFalse);
      expect(copy.name, 'Ember copy');
      expect(copy.style.shape, CornerShape.square);
      expect(BuiltInThemes.ember.style.shape, CornerShape.rounded);
      // Further changes update the copy instead of making more.
      await scrollTo(tester, chip('Floating bar'));
      await tester.tap(chip('Floating bar').first);
      await tester.pumpAndSettle();
      expect(h.store.customThemes, hasLength(1));
      expect(h.store.activeTheme.style.nav, NavStyle.floating);
      expect(h.store.activeTheme.style.shape, CornerShape.square);
      await h.finish(tester);
    });

    testWidgets('the theme editor saves every style control with the theme', (tester) async {
      final h = _Harness();
      final draft = BuiltInThemes.ember.copyWith(id: 'draft', name: 'Draft');
      await h.open(tester, home: ThemeEditorScreen(theme: draft, isNew: true));
      await scrollTo(tester, chip('Wide'));
      await tester.tap(chip('Wide').first);
      await scrollTo(tester, find.text('Terminal tabs'));
      await tester.tap(find.text('Terminal tabs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save theme'));
      await tester.pumpAndSettle();
      final saved = h.store.activeTheme;
      expect(saved.name, 'Draft');
      expect(saved.style.keys.gap, 6);
      expect(saved.style.terminal.showTabs, isTrue);
      await h.finish(tester);
    });
  });
}
