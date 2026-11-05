import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_motion.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/multiplex_app.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_backgrounds.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/app/theme_style.dart';
import 'package:multiplex/data/app_settings.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/theme_types.dart';
import 'package:multiplex/ui/appearance/appearance_screen.dart';
import 'package:multiplex/ui/appearance/theme_download.dart';
import 'package:multiplex/ui/appearance/theme_import.dart';
import 'package:multiplex/ui/appearance/theme_import_flow.dart';
import 'package:multiplex/ui/appearance/theme_repo_install.dart';
import 'package:multiplex/ui/appearance/theme_text_editor_screen.dart';
import 'package:multiplex/ui/common/theme_backdrop.dart';

/// A theme pack with three pictures, saved in a temporary folder.
class _Pack {
  _Pack(this.root);

  final Directory root;
  static const id = 'pack';
  static const names = ['a.png', 'b.png', 'c.png'];

  /// No drawn backdrops, so the steps are the three pictures and the plain colour.
  static final theme = BuiltInThemes.nord.copyWith(id: id, name: 'Pack', backgrounds: names, backdrops: const []);

  void writeFiles() {
    final dir = Directory('${root.path}${Platform.pathSeparator}$id')..createSync(recursive: true);
    for (final n in names) {
      File('${dir.path}${Platform.pathSeparator}$n').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0]);
    }
  }
}

/// Opens the app, or one screen, on a fresh store.
class _App {
  late VaultStore store;
  late SessionManager sessions;

  Future<void> open(WidgetTester tester, {ThemeSpec? theme, Widget? home}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = await VaultStore.open(MemoryBackend());
    sessions = SessionManager(store);
    if (theme != null) {
      store.saveTheme(theme);
      store.updateSettings(store.settings.copyWith(themeId: theme.id));
    }
    await tester.pumpWidget(home == null
        ? MultiplexApp(store: store, sessions: sessions)
        : AppScope(
            vault: store,
            manager: sessions,
            child: ListenableBuilder(
              listenable: store,
              builder: (_, _) => MaterialApp(theme: AppTheme.build(store.activeTheme), home: home),
            ),
          ));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    sessions.dispose();
  }
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('packs');
    ThemeBackgrounds.rootOverride = root;
  });
  tearDown(() {
    ThemeBackgrounds.rootOverride = null;
    root.deleteSync(recursive: true);
  });

  testWidgets('Next background on the Appearance screen moves through the pictures', (tester) async {
    final app = _App();
    await app.open(tester, theme: _Pack.theme, home: const AppearanceScreen());
    final button = find.textContaining('Next background');
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(app.store.activeTheme.activeBackground, 1);
    expect(find.text('Background 2 of 3: Your picture'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.textContaining('Next background'));
      await tester.pumpAndSettle();
    }
    expect(app.store.activeTheme.activeBackground, 0);
    await app.finish(tester);
  });

  testWidgets('a long press on Settings opens the switcher; a tap applies a theme and it stays open', (tester) async {
    final app = _App();
    await app.open(tester);
    await tester.longPress(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(find.text('Switch theme'), findsOneWidget);
    await tester.tap(find.text('Slate'));
    await tester.pumpAndSettle();
    expect(app.store.activeTheme.id, BuiltInThemes.slate.id);
    expect(find.text('Switch theme'), findsOneWidget);
    // A long press elsewhere on the bar does not open it again or change place.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.longPress(find.descendant(of: find.byType(NavigationBar), matching: find.text('Hosts')));
    await tester.pumpAndSettle();
    expect(find.text('Switch theme'), findsNothing);
    await app.finish(tester);
  });

  testWidgets('Ctrl+Shift+T opens the switcher from anywhere', (tester) async {
    final app = _App();
    await app.open(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Switch theme'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('the picture shows behind the main screens only when the style asks', (tester) async {
    _Pack(root).writeFiles();
    final app = _App();
    await app.open(tester, theme: _Pack.theme);
    expect(find.byType(ThemeBackdrop), findsNothing);
    app.store.saveTheme(_Pack.theme.copyWith(style: const ThemeStyle(backdrop: BackdropStyle(dim: 0.2, onScreens: true))));
    await tester.pumpAndSettle();
    final backdrop = tester.widget<ThemeBackdrop>(find.byType(ThemeBackdrop));
    expect(backdrop.slide, const PictureSlide('a.png'));
    // Behind lists the picture is dimmed at least 70 %.
    expect(backdrop.dim, BackdropStyle.minScreenDim);
    expect(tester.widget<ColoredBox>(find.byKey(ThemeBackdrop.dimKey)).color.a, closeTo(0.7, 0.01));
    await app.finish(tester);
  });

  test('motion: off, fast and normal, and off when the system asks', () {
    expect(AppMotion.resolve(MotionSpeed.off, reduceMotion: false).theme, Duration.zero);
    expect(AppMotion.resolve(MotionSpeed.fast, reduceMotion: false).theme, lessThan(AppMotion.resolve(MotionSpeed.normal, reduceMotion: false).theme));
    expect(AppMotion.resolve(MotionSpeed.normal, reduceMotion: true).sheet, AnimationStyle.noAnimation);
    final saved = AppSettings.fromJson(const AppSettings(motion: MotionSpeed.fast).toJson());
    expect(saved.motion, MotionSpeed.fast);
    expect(AppSettings.fromJson(const {}).motion, MotionSpeed.normal);
  });

  testWidgets('the motion setting sets the speed of theme changes', (tester) async {
    final app = _App();
    await app.open(tester);
    MaterialApp material() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material().themeAnimationDuration, const Duration(milliseconds: 250));
    app.store.updateSettings(app.store.settings.copyWith(motion: MotionSpeed.off));
    await tester.pumpAndSettle();
    expect(material().themeAnimationDuration, Duration.zero);
    await app.finish(tester);
  });

  testWidgets('Edit as text shows problems by line and saves once they are fixed', (tester) async {
    final app = _App();
    final theme = BuiltInThemes.ember.copyWith(id: 'mine', name: 'Mine');
    await app.open(tester, home: ThemeTextEditorScreen(theme: theme, isNew: true, pictures: const {}));
    final field = find.byType(TextField);
    final text = tester.widget<TextField>(field).controller!.text;
    await tester.enterText(field, text.replaceFirst('"shape": "rounded"', '"shape": "blob"'));
    await tester.tap(find.text('Save theme'));
    await tester.pumpAndSettle();
    final line = text.split('\n').indexWhere((l) => l.contains('"shape"')) + 1;
    expect(find.textContaining('Line $line: "shape" must be one of'), findsOneWidget);
    expect(app.store.customThemes, isEmpty);
    await tester.enterText(field, text.replaceFirst('"shape": "rounded"', '"shape": "round"'));
    await tester.tap(find.text('Save theme'));
    await tester.pumpAndSettle();
    expect(app.store.activeTheme.id, 'mine');
    expect(app.store.activeTheme.style.shape, CornerShape.round);
    await app.finish(tester);
  });

  testWidgets('Install theme from link installs the pack and uses it', (tester) async {
    final fetch = _MapFetcher({
      'https://api.github.com/repos/someone/omarchy-dusk-theme/contents': jsonEncode([
        {'name': 'alacritty.toml', 'type': 'file', 'size': 40, 'download_url': 'https://raw.githubusercontent.com/someone/omarchy-dusk-theme/main/alacritty.toml'},
        {'name': 'backgrounds', 'type': 'dir', 'size': 0, 'download_url': null},
      ]),
      'https://api.github.com/repos/someone/omarchy-dusk-theme/contents/backgrounds': jsonEncode([
        {'name': '1.png', 'type': 'file', 'size': 12, 'download_url': 'https://raw.githubusercontent.com/someone/omarchy-dusk-theme/main/backgrounds/1.png'},
      ]),
      'https://raw.githubusercontent.com/someone/omarchy-dusk-theme/main/alacritty.toml': utf8.encode('[colors.primary]'),
      'https://raw.githubusercontent.com/someone/omarchy-dusk-theme/main/backgrounds/1.png': [0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0],
    });
    final importer = ThemeImporter(
      parse: (_) => ImportedTheme(foreground: 0xFFEEEEEE, background: 0xFF111111, ansi: Uint32List.fromList(List.filled(16, 0xFF888888)), format: 'alacritty'),
    );
    final app = _App();
    await app.open(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ThemeImportFlow(context, installer: ThemeRepoInstaller(fetcher: fetch, importer: importer)).installFromRepo(),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://github.com/someone/omarchy-dusk-theme');
    await tester.runAsync(() async {
      await tester.tap(find.text('Install'));
      // Real file writes run outside the test clock.
      for (var i = 0; i < 50 && app.store.customThemes.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    final theme = app.store.activeTheme;
    expect(theme.name, 'Dusk');
    expect(theme.backgrounds, hasLength(1));
    expect(find.textContaining('Installed Dusk with 1 background picture'), findsOneWidget);
    await app.finish(tester);
  });
}

/// Answers downloads from a map of links.
class _MapFetcher implements ThemeFetcher {
  _MapFetcher(this.files);

  final Map<String, Object> files;

  @override
  Future<Uint8List> fetchBytes(Uri uri, {required int maxBytes, required ThemeImportException tooBig, Duration? limit, Map<String, String>? headers}) async {
    final file = files['$uri'];
    if (file == null) throw ThemeDownloadStatusException(404);
    return Uint8List.fromList(file is String ? utf8.encode(file) : (file as List<int>));
  }
}
