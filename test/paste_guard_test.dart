import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/data/app_settings.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/paste_guard.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/sessions/terminal_controller.dart';
import 'package:multiplex/src/rust/api/terminal.dart';
import 'package:multiplex/src/rust/api/terminal_types.dart';
import 'package:multiplex/ui/settings/settings_screen.dart';
import 'package:multiplex/ui/terminal/paste_confirm_dialog.dart';

/// A shell that keeps what was pasted instead of sending it.
class PasteShell implements RemoteShell {
  final pasted = <String>[];
  final _events = StreamController<ShellEvent>();

  @override
  Stream<ShellEvent> events() => _events.stream;

  @override
  TerminalFrame frame() => const TerminalFrame(
        rows: 2,
        cols: 20,
        lines: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true, shape: CursorShape.block, color: 0),
        scrollOffset: 0,
        scrollbackLen: 0,
        alternateScreen: false,
        mouseReporting: false,
        title: '',
        background: 0,
        foreground: 0,
      );

  @override
  void paste({required String text}) => pasted.add(text);

  @override
  String textBetween({required int startRow, required int startCol, required int endRow, required int endCol}) => '';

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasteGuard', () {
    test('a plain single line goes straight through', () {
      expect(PasteGuard.reasons('ls -la /var/log'), isEmpty);
      expect(PasteGuard.needsConfirm('git status'), isFalse);
    });

    test('several lines, or a line that ends in Enter, are stopped', () {
      expect(PasteGuard.reasons('cd /tmp\nls\n'), ['It has 2 lines. Each one runs as soon as it is pasted.']);
      expect(PasteGuard.reasons('make\r\n'), ['It ends with a line break, so it runs as soon as it is pasted.']);
    });

    test('risky commands are stopped and named', () {
      for (final text in ['sudo apt upgrade', 'rm -rf build', 'mkfs.ext4 /dev/sdb1', 'dd if=x.img of=y', 'cat x > /dev/sda', 'chmod -R 777 /srv']) {
        expect(PasteGuard.needsConfirm(text), isTrue, reason: text);
      }
      expect(PasteGuard.reasons('sudo rm -rf /'), ['It contains "sudo".', 'It contains "rm -rf".']);
    });

    test('look-alikes without the risky part pass', () {
      expect(PasteGuard.needsConfirm('pseudocode rm -r old'), isFalse);
      expect(PasteGuard.needsConfirm('chmod 755 run.sh'), isFalse);
    });
  });

  group('the setting', () {
    test('is on for vaults saved before it existed, and saves', () {
      expect(AppSettings.fromJson(const {}).confirmRiskyPaste, isTrue);
      final off = const AppSettings().copyWith(confirmRiskyPaste: false);
      expect(AppSettings.fromJson(off.toJson()).confirmRiskyPaste, isFalse);
    });

    testWidgets('can be turned off in Settings, Terminal', (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      await tester.pumpWidget(AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(theme: AppTheme.build(store.activeTheme), home: const SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check pastes first'));
      await tester.pump();
      expect(store.settings.confirmRiskyPaste, isFalse);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      sessions.dispose();
    });
  });

  group('TerminalController paste paths', () {
    late PasteShell shell;
    late TerminalController terminal;
    late List<String> asked;
    var answer = true;

    setUp(() {
      shell = PasteShell();
      terminal = TerminalController(shell: shell, title: 't', sessionId: 's');
      asked = [];
      answer = true;
      terminal.confirmPaste = (text, reasons) async {
        asked.add(text);
        return answer;
      };
    });

    test('a risky paste is asked about, and Cancel keeps it out', () async {
      answer = false;
      await terminal.pasteChecked('sudo reboot');
      expect(asked, ['sudo reboot']);
      expect(shell.pasted, isEmpty);
      answer = true;
      await terminal.pasteChecked('sudo reboot');
      expect(shell.pasted, ['sudo reboot']);
    });

    test('a safe paste is not asked about', () async {
      await terminal.pasteChecked('uptime');
      expect(asked, isEmpty);
      expect(shell.pasted, ['uptime']);
    });

    test('the clipboard paste is checked', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'line one\nline two'};
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      answer = false;
      await terminal.pasteClipboard();
      expect(asked, ['line one\nline two']);
      expect(shell.pasted, isEmpty);
    });

    test('text the app puts in itself (a recent command) is never asked about', () {
      terminal.paste('sudo systemctl restart nginx');
      expect(asked, isEmpty);
      expect(shell.pasted, ['sudo systemctl restart nginx']);
    });
  });

  group('PasteConfirmDialog', () {
    // Made outside the test's fake clock: the manager starts a timer.
    late VaultStore store;
    late SessionManager sessions;
    setUpAll(() async {
      store = await VaultStore.open(MemoryBackend());
      sessions = SessionManager(store);
    });

    Future<List<bool>> pump(WidgetTester tester) async {
      final results = <bool>[];
      await tester.pumpWidget(AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(
          theme: AppTheme.build(store.activeTheme),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => results.add(await PasteConfirmDialog.ask(context, 'cd /tmp\nsudo rm -rf x', PasteGuard.reasons('cd /tmp\nsudo rm -rf x'))),
                child: const Text('paste'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('paste'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('shows the text and why, and Paste says yes', (tester) async {
      final results = await pump(tester);
      expect(find.text('Paste this?'), findsOneWidget);
      expect(find.text('cd /tmp\nsudo rm -rf x'), findsOneWidget);
      expect(find.text('It contains "sudo".'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Paste'));
      await tester.pumpAndSettle();
      expect(results, [true]);
    });

    testWidgets('Cancel says no', (tester) async {
      final results = await pump(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  });
}
