import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show AnyhowException;
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultterm/app/app_scope.dart';
import 'package:vaultterm/app/theme.dart';
import 'package:vaultterm/app/theme_spec.dart';
import 'package:vaultterm/data/app_settings.dart';
import 'package:vaultterm/data/vault_backend.dart';
import 'package:vaultterm/data/vault_store.dart';
import 'package:vaultterm/sessions/session_manager.dart';
import 'package:vaultterm/src/rust/api/theme_types.dart';
import 'package:vaultterm/ui/appearance/appearance_screen.dart';
import 'package:vaultterm/ui/appearance/color_tools.dart';
import 'package:vaultterm/ui/appearance/font_file.dart';
import 'package:vaultterm/ui/appearance/theme_download.dart';
import 'package:vaultterm/ui/appearance/theme_export.dart';
import 'package:vaultterm/ui/appearance/theme_gallery.dart';
import 'package:vaultterm/ui/appearance/theme_import.dart';
import 'package:vaultterm/ui/appearance/theme_preview.dart';

/// Test data that would otherwise need the native library or real files.
abstract final class _Fixtures {
  /// A theme as the Rust reader would return it.
  static ImportedTheme imported({String? name, int blue = 0xFF7AA2F7, int background = 0xFF1A1B26, int? cursor}) => ImportedTheme(
    name: name,
    foreground: 0xFFC0CAF5,
    background: background,
    cursor: cursor,
    ansi: Uint32List.fromList([
      0xFF15161E, 0xFFF7768E, 0xFF9ECE6A, 0xFFE0AF68, blue, 0xFFBB9AF7, 0xFF7DCFFF, 0xFFA9B1D6, //
      0xFF414868, 0xFFF7768E, 0xFF9ECE6A, 0xFFE0AF68, blue, 0xFFBB9AF7, 0xFF7DCFFF, 0xFFC0CAF5,
    ]),
    format: 'alacritty',
  );

  /// The smallest TrueType file that carries a family name.
  static Uint8List fontWithFamily(String family) {
    final name = [
      for (final c in family.codeUnits) ...[c >> 8, c & 0xFF],
    ];
    final data = ByteData(12 + 16 + 6 + 12 + name.length);
    data.setUint32(0, 0x00010000); // TrueType marker
    data.setUint16(4, 1); // one table
    data.setUint32(12, 0x6E616D65); // "name"
    data.setUint32(20, 28); // where the table starts
    data.setUint32(24, 18 + name.length);
    data.setUint16(30, 1); // one name record
    data.setUint16(32, 18); // strings start after the record
    data.setUint16(34, 3); // Windows
    data.setUint16(36, 1);
    data.setUint16(38, 0x409); // English
    data.setUint16(40, 1); // family name
    data.setUint16(42, name.length);
    data.setUint16(44, 0);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(46, 46 + name.length, name);
    return bytes;
  }
}

void main() {
  group('colour tools', () {
    test('hex codes go both ways', () {
      expect(ColorHex.format(0xFF1E1E2E), '#1e1e2e');
      expect(ColorHex.parse('#1E1E2E'), 0xFF1E1E2E);
      expect(ColorHex.parse('abc'), 0xFFAABBCC);
      expect(ColorHex.parse('#12345'), isNull);
      expect(ColorHex.parse('red'), isNull);
    });

    test('contrast runs from 1 to 21', () {
      expect(ColorContrast.ratio(0xFF000000, 0xFFFFFFFF), closeTo(21, 0.01));
      expect(ColorContrast.ratio(0xFF777777, 0xFF777777), closeTo(1, 0.01));
    });

    test('palette colours have names', () {
      expect(AnsiNames.of(1), 'Red');
      expect(AnsiNames.of(9), 'Bright red');
      expect(AnsiNames.of(15), 'Bright white');
    });
  });

  group('theme import', () {
    test('VaultTerm JSON comes back with the same colours and a new id', () {
      final original = BuiltInThemes.tokyoNight;
      final read = ThemeImporter(parse: (_) => throw StateError('JSON must not reach the theme reader')).read(ThemeExport.json(original));
      expect(read.id, isNot(original.id));
      expect(read.name, original.name);
      expect(read.ansi, original.ansi);
      expect(read.background, original.background);
      expect(read.accent, original.accent);
      expect(read.builtIn, isFalse);
    });

    test('JSON that is not a theme is refused with a clear message', () {
      final importer = ThemeImporter(parse: (_) => throw StateError('unused'));
      expect(() => importer.read('{"hosts": []}'), throwsA(isA<ThemeImportException>()));
      expect(() => importer.read('{ broken'), throwsA(isA<ThemeImportException>()));
      expect(() => importer.read('   '), throwsA(isA<ThemeImportException>()));
    });

    test('other formats go through the theme reader and get a name', () {
      final unnamed = ThemeImporter(parse: (_) => _Fixtures.imported()).read('[colors]', sourceName: 'Tokyo Night');
      expect(unnamed.name, 'Tokyo Night');
      expect(unnamed.cursor, unnamed.foreground, reason: 'no cursor colour falls back to the text colour');

      final named = ThemeImporter(parse: (_) => _Fixtures.imported(name: 'Storm')).read('[colors]', sourceName: 'file');
      expect(named.name, 'Storm');

      final nameless = ThemeImporter(parse: (_) => _Fixtures.imported()).read('[colors]');
      expect(nameless.name, ThemeImporter.fallbackName);
    });

    test('the accent is the blue, or the cursor when the blue barely shows', () {
      final blue = ThemeImporter(parse: (_) => _Fixtures.imported()).read('x');
      expect(blue.accent, 0xFF7AA2F7);

      final dim = ThemeImporter(parse: (_) => _Fixtures.imported(blue: 0xFF1C1D28, cursor: 0xFFFF9E64)).read('x');
      expect(dim.accent, 0xFFFF9E64);
    });

    test('reader errors become a sentence that says what to do', () {
      final importer = ThemeImporter(parse: (_) => throw AnyhowException('the theme has no background colour'));
      expect(
        () => importer.read('foreground = #fff'),
        throwsA(
          isA<ThemeImportException>().having(
            (e) => e.message,
            'message',
            startsWith('The theme has no background colour. VaultTerm can import'),
          ),
        ),
      );
    });

    test('files that are too big or not text are refused', () {
      expect(() => ThemeImporter.decode(List.filled(ThemeImporter.maxBytes + 1, 0x41)), throwsA(isA<ThemeImportException>()));
      expect(() => ThemeImporter.decode([0xFF, 0xFE, 0x00, 0x01]), throwsA(isA<ThemeImportException>()));
      expect(ThemeImporter.decode(utf8.encode('\uFEFF[colors]')), '[colors]');
    });

    test('names come from file names and links', () {
      expect(ThemeSourceName.fromFileName('tokyo-night.toml'), 'Tokyo Night');
      expect(ThemeSourceName.fromFileName(r'C:\themes\catppuccin_mocha.conf'), 'Catppuccin Mocha');
      expect(ThemeSourceName.fromFileName('Dracula'), 'Dracula');
      expect(ThemeSourceName.fromUrl(Uri.parse('https://example.com/a/gruvbox-dark.toml')), 'Gruvbox Dark');
    });

    test('links must be https; GitHub file pages become raw file links', () {
      expect(() => ThemeDownloader.parseLink('http://example.com/theme.toml'), throwsA(isA<ThemeImportException>()));
      expect(() => ThemeDownloader.parseLink('not a link'), throwsA(isA<ThemeImportException>()));
      expect(
        ThemeDownloader.parseLink('https://github.com/alacritty/alacritty-theme/blob/master/themes/nord.toml').toString(),
        'https://raw.githubusercontent.com/alacritty/alacritty-theme/master/themes/nord.toml',
      );
      expect(ThemeDownloader.parseLink('https://example.com/x.conf').toString(), 'https://example.com/x.conf');
    });
  });

  group('font files', () {
    test('the family name is read from inside the font', () {
      final info = FontFileInfo.read(_Fixtures.fontWithFamily('Fira Code'));
      expect(info.isFont, isTrue);
      expect(info.family, 'Fira Code');
    });

    test('a file that is not a font is recognised', () {
      expect(FontFileInfo.read(Uint8List.fromList(utf8.encode('hello, I am text'))).isFont, isFalse);
      expect(FontFileInfo.read(Uint8List(3)).isFont, isFalse);
    });
  });

  group('screens', () {
    late VaultStore store;
    late SessionManager sessions;

    Future<void> open(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      store = await VaultStore.open(MemoryBackend());
      sessions = SessionManager(store);
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: ListenableBuilder(
            listenable: store,
            builder: (_, _) => MaterialApp(theme: AppTheme.build(store.activeTheme), home: const AppearanceScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Lets the store's delayed save run and stops the session ticker, so
    // no timer is left behind.
    Future<void> finish(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 1));
      sessions.dispose();
    }

    // Lists build lazily, so text further down only exists once shown.
    Future<void> scrollTo(WidgetTester tester, String text) =>
        tester.scrollUntilVisible(
          find.text(text),
          300,
          // The page's own list, not the scrolling inside a text field.
          scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
        );

    testWidgets('the preview fits a small card and a large font', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(width: 160, height: 100, child: ThemePreview(theme: BuiltInThemes.nord)),
              SizedBox(
                width: 200,
                child: ThemePreview(theme: BuiltInThemes.paper, fontSize: 28, lineHeight: 1.6, cursorStyle: CursorStyle.underline),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('host'), findsNWidgets(2));
    });

    for (final size in [const Size(360, 740), const Size(1280, 800)]) {
      testWidgets('tapping a theme uses it at once (${size.width.round()} wide)', (tester) async {
        await open(tester, size);
        expect(find.text('Built-in'), findsOneWidget);

        final semantics = tester.ensureSemantics();
        // Every tap target is at least 48 dp and has a label.
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await tester.tap(find.text('Nord'));
        await tester.pumpAndSettle();
        expect(store.settings.themeId, BuiltInThemes.nord.id);
        expect(find.text('Nord applied'), findsOneWidget);
        expect(find.bySemanticsLabel('Nord theme, selected'), findsOneWidget);
        semantics.dispose();
        final active = find.byWidgetPredicate((w) => w is ThemeCard && w.active);
        expect(active, findsOneWidget);
        expect(tester.widget<ThemeCard>(active).theme.id, BuiltInThemes.nord.id);

        // The rest of the page lays out without overflowing.
        await scrollTo(tester, 'Your themes');
        await scrollTo(tester, 'Blinking cursor');
        await tester.ensureVisible(find.text('Bar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bar'));
        await tester.pumpAndSettle();
        expect(store.settings.cursorStyle, CursorStyle.bar);
        await finish(tester);
      });
    }

    testWidgets('large text does not break the page or the editor', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, const Size(360, 740));

      // The import sheet and the paste dialog.
      await tester.tap(find.byTooltip('Import theme'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // At this size the sheet scrolls, so bring the choice into view first.
      await tester.ensureVisible(find.text('Paste text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste text'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await scrollTo(tester, 'Your themes');
      await scrollTo(tester, 'Blinking cursor');
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Create theme'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Terminal colours');
      await scrollTo(tester, 'Bright');
      expect(tester.takeException(), isNull);

      // The colour dialog, opened from the red swatch.
      final semantics = tester.ensureSemantics();
      final red = find.bySemanticsLabel(RegExp(r'^Red, #'));
      await tester.ensureVisible(red);
      await tester.pumpAndSettle();
      await tester.tap(red);
      await tester.pumpAndSettle();
      expect(find.text('Use colour'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await finish(tester);
    });

    testWidgets('Create theme saves a copy of the theme in use and uses it', (tester) async {
      await open(tester, const Size(360, 740));
      await tester.tap(find.byTooltip('Create theme'));
      await tester.pumpAndSettle();
      expect(find.text('New theme'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      // Making the background the same as the text brings up the warning.
      expect(find.textContaining('hard to read'), findsNothing);
      await tester.tap(find.text('Background'));
      await tester.pumpAndSettle();
      // The colour dialog's swatches and sliders are big enough to hit too.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.enterText(find.widgetWithText(TextField, 'Hex colour'), '#e6e1d6');
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(find.textContaining('hard to read'), findsOneWidget);
      semantics.dispose();

      await scrollTo(tester, 'Terminal colours');
      await scrollTo(tester, 'Bright');

      await tester.tap(find.text('Save theme'));
      await tester.pumpAndSettle();
      expect(store.customThemes, hasLength(1));
      final saved = store.customThemes.single;
      expect(saved.name, '${BuiltInThemes.ember.name} copy');
      expect(saved.background, 0xFFE6E1D6);
      expect(store.settings.themeId, saved.id);
      await finish(tester);
    });

    testWidgets('a pasted VaultTerm theme opens for review and is saved', (tester) async {
      await open(tester, const Size(1280, 800));
      await tester.tap(find.byTooltip('Import theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste text'));
      await tester.pumpAndSettle();

      final shared = BuiltInThemes.gruvboxDark.copyWith(id: 'x', name: 'Shared gruvbox');
      await tester.enterText(find.byType(TextField), ThemeExport.json(shared));
      await tester.tap(find.widgetWithText(FilledButton, 'Import theme'));
      await tester.pumpAndSettle();
      expect(find.text('Review imported theme'), findsOneWidget);

      await tester.tap(find.text('Save theme'));
      await tester.pumpAndSettle();
      final saved = store.customThemes.single;
      expect(saved.name, 'Shared gruvbox');
      expect(saved.id, isNot('x'));
      expect(saved.ansi, BuiltInThemes.gruvboxDark.ansi);
      expect(store.activeTheme.id, saved.id);
      await finish(tester);
    });
  });
}
