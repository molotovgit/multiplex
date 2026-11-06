import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/files/preview/pdf_document.dart';
import 'package:multiplex/ui/files/preview/preview_files.dart';
import 'package:multiplex/ui/files/preview/preview_screen.dart';

import 'support/files_fixtures.dart';

/// A 1 by 1 pixel PNG.
final pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  late Directory temp;

  setUpAll(() async {
    Fixtures.store = await VaultStore.open(MemoryBackend());
    Fixtures.sessions = SessionManager(Fixtures.store);
  });
  tearDownAll(() => Fixtures.sessions.dispose());

  setUp(() {
    temp = Directory.systemTemp.createTempSync('mpx-preview-');
    PreviewFiles.tempFolder = () async => temp;
    PreviewScreen.defaultTransfer = FakeTransfer.new;
  });
  tearDown(() {
    PdfDocument.debugSupported = null;
    temp.deleteSync(recursive: true);
  });

  Directory previews() => Directory('${temp.path}${Platform.pathSeparator}${PreviewFiles.folder}');
  List<FileSystemEntity> copies() => previews().existsSync() ? previews().listSync() : [];

  /// Lets real file work (writing the copy, deleting it) finish: each
  /// step needs real time, then a pump to deliver its result.
  Future<void> settleFiles(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  FakeFiles serverWith(String name, List<int> bytes, {int? size}) {
    final tree = Fixtures.tree();
    tree['/home/ann']!.add(Fixtures.entry('/home/ann', name, size: size ?? bytes.length));
    return FakeFiles(tree)..blobs['/home/ann/$name'] = bytes;
  }

  test('pictures and PDFs can be previewed, other files cannot', () {
    expect(PreviewKind.of('photo.JPG'), PreviewKind.image);
    expect(PreviewKind.of('anim.gif'), PreviewKind.image);
    expect(PreviewKind.of('shot.webp'), PreviewKind.image);
    expect(PreviewKind.of('report.pdf'), PreviewKind.pdf);
    expect(PreviewKind.of('notes.txt'), isNull);
    expect(PreviewKind.of('pdf'), isNull);
  });

  test('old left-over copies are swept away when a new preview opens', () async {
    final dir = previews()..createSync(recursive: true);
    final old = File('${dir.path}${Platform.pathSeparator}old.png')..writeAsBytesSync(pixel);
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
    final recent = File('${dir.path}${Platform.pathSeparator}recent.png')..writeAsBytesSync(pixel);
    final files = serverWith('photo.png', pixel);
    final copy = await PreviewFiles().fetch(files, Fixtures.entry('/home/ann', 'photo.png'), FakeTransfer());
    expect(copy.readAsBytesSync(), pixel);
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue, reason: 'may belong to a preview that is still open');
    await PreviewFiles.discard(copy);
    expect(copy.existsSync(), isFalse);
  });

  testWidgets('a picture opens in the zoomable preview and its copy goes when it closes', (tester) async {
    Fixtures.phone(tester);
    final files = serverWith('photo.png', pixel);
    await Fixtures.showFiles(tester, FakeSsh(files));
    await tester.tap(find.text('photo.png'));
    await tester.pump();
    await settleFiles(tester);
    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(copies(), hasLength(1));
    expect(find.byTooltip('Download to this device'), findsOneWidget);
    await Fixtures.checkTouchRules(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settleFiles(tester);
    expect(find.byType(PreviewScreen), findsNothing);
    expect(copies(), isEmpty);
  });

  testWidgets('a picture too big to preview is offered as a download', (tester) async {
    final files = serverWith('huge.jpg', pixel, size: PreviewKind.maxImageBytes + 1);
    await Fixtures.showFiles(tester, FakeSsh(files));
    await tester.tap(find.text('huge.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('Too big to preview'), findsOneWidget);
    expect(files.calls.where((c) => c.startsWith('download')), isEmpty);
  });

  testWidgets('a PDF swipes and steps between pages, and is closed afterwards', (tester) async {
    Fixtures.phone(tester);
    PdfDocument.debugSupported = true;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(PdfDocument.channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'open' => {'id': 7, 'sizes': [612.0, 792.0, 612.0, 792.0, 792.0, 612.0]},
        'render' => Uint8List.fromList(pixel),
        _ => null,
      };
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(PdfDocument.channel, null));
    final files = serverWith('report.pdf', utf8.encode('%PDF-1.4'));
    await Fixtures.showFiles(tester, FakeSsh(files));
    await tester.tap(find.text('report.pdf'));
    await tester.pump();
    await settleFiles(tester);
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await Fixtures.checkTouchRules(tester);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settleFiles(tester);
    expect(calls.first, 'open');
    expect(calls.last, 'close');
    expect(copies(), isEmpty);
  });

  testWidgets('away from Android a PDF says how to open it instead', (tester) async {
    PdfDocument.debugSupported = false;
    final files = serverWith('report.pdf', utf8.encode('%PDF-1.4'));
    await Fixtures.showFiles(tester, FakeSsh(files));
    await tester.tap(find.text('report.pdf'));
    await tester.pump();
    await settleFiles(tester);
    expect(find.textContaining('PDF preview works on Android'), findsOneWidget);
  });
}
