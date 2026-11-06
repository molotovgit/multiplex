import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/sftp.dart';
import 'package:multiplex/src/rust/api/sftp_types.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/files/folder_browser.dart';
import 'package:multiplex/ui/terminal/links/link_detector.dart';
import 'package:multiplex/ui/terminal/links/link_sheet.dart';
import 'package:multiplex/ui/terminal/links/screen_links.dart';
import 'package:multiplex/ui/terminal/terminal_marks.dart';

List<(LinkKind, String)> found(String text) => [for (final l in LinkDetector.find(text)) (l.kind, l.text)];

TextRun run(int col, String text, {int? width}) => TextRun(col: col, width: width ?? text.length, text: text, fg: 0, bg: 0, style: 0);

TerminalLine line(int key, List<TextRun> runs) => TerminalLine(key: BigInt.from(key), runs: runs);

/// A server with a few folders; listing a file fails like on a real one.
class FolderFiles implements RemoteFiles {
  final folders = {'/home/ann', '/home/ann/logs', '/etc/nginx'};

  @override
  Future<String> home() async => '/home/ann';
  @override
  Future<String> canonicalize({required String path}) async => path.replaceFirst('~', '/home/ann');
  @override
  Future<List<RemoteEntry>> list({required String dir}) async => folders.contains(dir) ? const [] : throw AnyhowException('not a folder');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LinkDetector', () {
    test('finds web links and leaves sentence punctuation out', () {
      expect(found('see https://example.com/a?b=1.'), [(LinkKind.url, 'https://example.com/a?b=1')]);
      expect(found('(docs: http://x.org/wiki/A_(b)) and more'), [(LinkKind.url, 'http://x.org/wiki/A_(b)')]);
      expect(found('(at https://x.org/a)'), [(LinkKind.url, 'https://x.org/a')]);
      expect(found('just https:// here'), isEmpty);
    });

    test('finds IPv4 addresses with or without a port', () {
      expect(found('inet 192.168.1.20/24 brd'), [(LinkKind.address, '192.168.1.20')]);
      expect(found('listening on 0.0.0.0:8080,'), [(LinkKind.address, '0.0.0.0:8080')]);
      expect(found('inet addr:10.0.0.5'), [(LinkKind.address, '10.0.0.5')]);
    });

    test('does not take versions or out-of-range numbers for addresses', () {
      expect(found('version 1.2.3.4.5'), isEmpty);
      expect(found('999.1.1.1'), isEmpty);
      expect(found('build 10.0.19045.1'), isEmpty);
    });

    test('finds IPv6 addresses, plain and with a port in brackets', () {
      expect(found('inet6 fe80::1c2b:3cff:fe4d:5e6f/64'), [(LinkKind.address, 'fe80::1c2b:3cff:fe4d:5e6f')]);
      expect(found('connect [2001:db8::1]:22 now'), [(LinkKind.address, '[2001:db8::1]:22')]);
      expect(found('loopback ::1.'), [(LinkKind.address, '::1')]);
    });

    test('times, MAC addresses and C++ names are not addresses', () {
      expect(found('at 12:30:45 today'), isEmpty);
      expect(found('ether aa:bb:cc:dd:ee:ff'), isEmpty);
      expect(found('std::vector<int>'), isEmpty);
    });

    test('finds absolute and home paths', () {
      expect(found('cat /etc/hosts.'), [(LinkKind.path, '/etc/hosts')]);
      expect(found('ann@box:~/src/app\$ '), [(LinkKind.path, '~/src/app')]);
      expect(found('PATH=/usr/bin:/bin'), [(LinkKind.path, '/usr/bin'), (LinkKind.path, '/bin')]);
      expect(found('src/main.rs:12 and /var/log/syslog:3'), [(LinkKind.path, '/var/log/syslog')]);
    });

    test('a lone slash, a fraction or "and/or" is not a path', () {
      expect(found('a / b'), isEmpty);
      expect(found('1/2 and/or'), isEmpty);
    });

    test('a URL wins over the path inside it', () {
      expect(found('get https://example.com/files/a.txt'), [(LinkKind.url, 'https://example.com/files/a.txt')]);
    });

    test('knows where each link is in the text', () {
      final links = LinkDetector.find('x /tmp/a y');
      expect((links.single.start, links.single.end), (2, 8));
    });
  });

  group('RowText and ScreenLinks', () {
    test('rebuilds trimmed gaps and places wide characters on their cells', () {
      // "漢" covers cells 0-1, then a path from cell 3.
      final row = RowText.of(line(1, [run(0, '漢', width: 2), run(3, '/etc/x')]));
      expect(row.text, '漢 /etc/x');
      expect(row.span(0, 2, 8), const CellSpan(0, 3, 6));
    });

    test('finds the links of a frame by screen row and cell', () {
      final frame = TerminalFrame(
        rows: 2,
        cols: 40,
        lines: [
          line(1, [run(0, 'nothing here')]),
          line(2, [run(0, 'open '), run(5, 'https://a.io')]),
        ],
        cursor: const TerminalCursor(row: 0, col: 0, visible: true, shape: CursorShape.block, color: 0),
        scrollOffset: 0,
        scrollbackLen: 0,
        alternateScreen: false,
        mouseReporting: false,
        title: '',
        background: 0,
        foreground: 0,
      );
      final links = ScreenLinks().of(frame);
      expect(links.single.span, const CellSpan(1, 5, 12));
      expect(ScreenLinks.at(links, 1, 16)?.link.text, 'https://a.io');
      expect(ScreenLinks.at(links, 1, 17), isNull);
      expect(ScreenLinks.at(links, 0, 5), isNull);
    });
  });

  group('LinkSheet', () {
    // Made outside the test's fake clock: the manager starts a timer.
    late VaultStore store;
    late SessionManager sessions;
    setUpAll(() async {
      store = await VaultStore.open(MemoryBackend());
      sessions = SessionManager(store);
    });

    Future<void> pumpSheet(WidgetTester tester, DetectedLink link, {ValueChanged<String>? onOpenPath, UrlOpener? openUrl}) async {
      await tester.pumpWidget(AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          theme: AppTheme.build(store.activeTheme),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => LinkSheet.show(context, link, onOpenPath: onOpenPath, openUrl: openUrl ?? (_) async => true),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a URL opens in the browser', (tester) async {
      final opened = <Uri>[];
      await pumpSheet(tester, const DetectedLink(LinkKind.url, 0, 12, 'https://a.io'), openUrl: (uri) async {
        opened.add(uri);
        return true;
      });
      expect(find.text('Open in Files'), findsNothing);
      await tester.tap(find.text('Open in browser'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://a.io')]);
      expect(find.text('Open in browser'), findsNothing);
    });

    testWidgets('says so when no app opens the link', (tester) async {
      await pumpSheet(tester, const DetectedLink(LinkKind.url, 0, 12, 'https://a.io'), openUrl: (_) async => false);
      await tester.tap(find.text('Open in browser'));
      await tester.pumpAndSettle();
      expect(find.text('No app could open this link'), findsOneWidget);
    });

    testWidgets('a path opens in Files; an address only copies', (tester) async {
      final paths = <String>[];
      await pumpSheet(tester, const DetectedLink(LinkKind.path, 0, 8, '~/logs/a'), onOpenPath: paths.add);
      expect(find.text('Open in browser'), findsNothing);
      await tester.tap(find.text('Open in Files'));
      await tester.pumpAndSettle();
      expect(paths, ['~/logs/a']);
    });

    testWidgets('copy puts the link on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpSheet(tester, const DetectedLink(LinkKind.address, 0, 8, '10.0.0.5'));
      expect(find.text('Open in browser'), findsNothing);
      expect(find.text('Open in Files'), findsNothing);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, '10.0.0.5');
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('FolderBrowser.start(at:)', () {
    test('opens a folder by its home path', () async {
      final browser = FolderBrowser(() async => FolderFiles());
      await browser.start(at: '~/logs');
      expect(browser.path, '/home/ann/logs');
    });

    test('opens the folder of a file', () async {
      final browser = FolderBrowser(() async => FolderFiles());
      await browser.start(at: '/etc/nginx/nginx.conf');
      expect(browser.path, '/etc/nginx');
    });

    test('stays home when the path cannot be opened', () async {
      final browser = FolderBrowser(() async => FolderFiles());
      await browser.start(at: '/nowhere/at/all');
      expect(browser.path, '/home/ann');
    });
  });
}
