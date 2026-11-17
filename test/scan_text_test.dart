import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/platform/text_scanner.dart';
import 'package:multiplex/ui/computers/scan_text.dart';

void main() {
  const desk = Host(id: 'c', label: 'Desk', address: 'desk', computer: true);
  final picture = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

  Future<void> sheet(WidgetTester tester, ReadPicture read) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextReadSheet(host: desk, picture: picture, read: read),
        ),
      ),
    );
  }

  testWidgets('the text shows once the computer has read it, and says where it is', (tester) async {
    final answer = Completer<TextReading>();
    Uint8List? sent;
    await sheet(tester, (p) {
      sent = p;
      return answer.future;
    });
    expect(find.text('Desk is reading the picture…'), findsOneWidget);
    expect(sent, picture);
    answer.complete(const TextReading('Meeting moved to 14:30\nRoom 204', ['eng']));
    await tester.pumpAndSettle();
    expect(find.text('On Desk\'s clipboard'), findsOneWidget);
    expect(find.text('Meeting moved to 14:30\nRoom 204'), findsOneWidget);

    // The phone's own clipboard only when asked.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    expect(copied, isEmpty);
    await tester.tap(find.text('Copy here too'));
    await tester.pump();
    expect(copied, ['Meeting moved to 14:30\nRoom 204']);
    // Let the toast go.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a picture without readable text says so, and which languages the computer reads', (tester) async {
    await sheet(tester, (_) async => const TextReading('', ['eng', 'rus']));
    await tester.pumpAndSettle();
    expect(find.text('No text could be read in the picture'), findsOneWidget);
    expect(find.textContaining('Desk reads: eng, rus'), findsOneWidget);
    expect(find.text('Copy here too'), findsNothing);
  });

  testWidgets('a computer that cannot read says why', (tester) async {
    await sheet(tester, (_) async => throw Exception('Reading text needs tesseract and at least one language for it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('needs tesseract'), findsOneWidget);
  });

  test('pictures are told from other files by their names', () {
    for (final name in ['IMG_2041.JPG', 'scan.jpeg', 'page.png', 'a.webp', 'x.HEIC']) {
      expect(ScanText.isPicture(name), isTrue, reason: name);
    }
    for (final name in ['notes.txt', 'report.pdf', 'jpg', 'archive.tar.gz', 'picture.png.zip']) {
      expect(ScanText.isPicture(name), isFalse, reason: name);
    }
  });

  test('the scanner hands over the picture, or nothing when the user backs out', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('multiplex/textscan');
    Object? answer = Uint8List.fromList([1, 2, 3]);
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add('${call.method} ${call.arguments ?? ''}'.trim());
      final now = answer;
      if (now is PlatformException) throw now;
      return answer;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    const scanner = TextScanner();
    expect(await scanner.scan(), [1, 2, 3]);
    expect(await scanner.shrink('/cache/shared/page.jpg'), [1, 2, 3]);
    expect(calls, ['scan', 'shrink /cache/shared/page.jpg']);
    answer = null;
    expect(await scanner.scan(), isNull);
    // No scanner on this phone: a sentence, not a crash.
    answer = PlatformException(code: 'unavailable', message: 'Google Play services is missing');
    expect(() => scanner.scan(), throwsA(isA<Exception>().having((e) => '$e', 'words', contains('Google Play services is missing'))));
    expect(await scanner.shrink('/x'), isNull);
  });
}
