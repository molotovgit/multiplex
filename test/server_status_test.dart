import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/app_scope.dart';
import 'package:multiplex/app/theme.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/ui/hosts/host_tile.dart';
import 'package:multiplex/ui/hosts/server_stats.dart';
import 'package:multiplex/ui/hosts/server_status_card.dart';
import 'package:multiplex/ui/hosts/server_status_controller.dart';

/// What the status command prints on a typical Linux server.
const linuxOutput = '''
cpu  1000 0 500 8000 500 0 0 0 0 0
cpu  1060 0 530 8090 520 0 0 0 0 0
MemTotal:        8000000 kB
MemFree:          500000 kB
MemAvailable:    6000000 kB
Buffers:          100000 kB
Cached:          1000000 kB
load 0.52 0.41 0.30 2/345 6789
uptime 266400.55 1000000.00
disk /dev/sda1 104857600 52428800 52428800 50% /
''';

void main() {
  group('parse', () {
    test('reads CPU, memory, disk, load and uptime', () {
      final s = ServerStats.parse(linuxOutput)!;
      // 200 ticks passed, 110 of them idle or waiting: 45 % busy.
      expect(s.cpuPercent, closeTo(45, 0.01));
      expect(s.memTotalKb, 8000000);
      expect(s.memUsedKb, 2000000);
      expect(s.memFraction, closeTo(0.25, 1e-9));
      expect((s.diskUsedKb, s.diskTotalKb), (52428800, 104857600));
      expect(s.load, [0.52, 0.41, 0.30]);
      expect(s.uptime, const Duration(days: 3, hours: 2));
    });

    test('old kernels without MemAvailable count free, buffers and cache', () {
      final s = ServerStats.parse(linuxOutput.replaceAll(RegExp(r'MemAvailable:.*\n'), ''))!;
      expect(s.memUsedKb, 8000000 - 1600000);
    });

    test('a file system name with spaces still reads the right columns', () {
      final s = ServerStats.parse(linuxOutput.replaceFirst('/dev/sda1', 'my disk 1'))!;
      expect(s.diskTotalKb, 104857600);
    });

    test('other systems and empty output are not available', () {
      expect(ServerStats.parse('unsupported\n'), isNull);
      expect(ServerStats.parse(''), isNull);
      expect(ServerStats.parse('sh: head: not found'), isNull);
    });

    test('one CPU sample gives no percentage but keeps the rest', () {
      final s = ServerStats.parse(linuxOutput.replaceFirst(RegExp(r'cpu .*\n'), ''))!;
      expect(s.cpuPercent, isNull);
      expect(s.memTotalKb, 8000000);
    });

    test('the command is one sh script that works in any login shell', () {
      expect(ServerStats.command, startsWith("sh -c '"));
      expect(ServerStats.command, endsWith("'"));
      // A single quote inside would end the script early.
      expect("'".allMatches(ServerStats.command).length, 2);
      expect(ServerStats.command, contains('/proc/stat'));
      expect(ServerStats.command, contains('echo unsupported'));
    });
  });

  group('format', () {
    test('sizes and uptime read naturally', () {
      expect(StatsFormat.kib(512), '512 KB');
      expect(StatsFormat.kib(2000000), '1.9 GB');
      expect(StatsFormat.kib(104857600), '100 GB');
      expect(StatsFormat.uptime(const Duration(minutes: 5)), '5 min');
      expect(StatsFormat.uptime(const Duration(hours: 3, minutes: 12)), '3 h 12 min');
      expect(StatsFormat.uptime(const Duration(days: 1, hours: 4)), '1 day 4 h');
      expect(StatsFormat.uptime(const Duration(days: 12)), '12 days 0 h');
    });
  });

  group('controller', () {
    // testWidgets runs with fake timers, so the periodic readings can be
    // stepped through without waiting.
    testWidgets('reads every period while running, and not after stop', (tester) async {
      var calls = 0;
      final c = ServerStatusController((_) async {
        calls++;
        return linuxOutput;
      });
      c.start();
      await tester.pump();
      expect(calls, 1);
      expect(c.phase, StatusPhase.ready);
      await tester.pump(const Duration(seconds: 15));
      expect(calls, 4);
      c.stop();
      await tester.pump(const Duration(seconds: 15));
      expect(calls, 4);
      c.dispose();
    });

    testWidgets('skips readings while not visible', (tester) async {
      var calls = 0;
      var visible = true;
      final c = ServerStatusController((_) async {
        calls++;
        return linuxOutput;
      }, isVisible: () => visible);
      c.start();
      await tester.pump();
      visible = false;
      await tester.pump(const Duration(seconds: 20));
      expect(calls, 1);
      visible = true;
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 2);
      c.dispose();
    });

    testWidgets('a non-Linux server stops the readings for good', (tester) async {
      var calls = 0;
      final c = ServerStatusController((_) async {
        calls++;
        return 'unsupported';
      });
      c.start();
      await tester.pump(const Duration(seconds: 20));
      expect(calls, 1);
      expect(c.phase, StatusPhase.unsupported);
      expect(c.running, isFalse);
      c.dispose();
    });

    testWidgets('a failed reading keeps the last numbers', (tester) async {
      var fail = false;
      final c = ServerStatusController((_) async {
        if (fail) throw 'connection lost';
        return linuxOutput;
      });
      c.start();
      await tester.pump();
      fail = true;
      await tester.pump(const Duration(seconds: 5));
      expect(c.phase, StatusPhase.failed);
      expect(c.error, 'connection lost');
      expect(c.stats, isNotNull);
      c.dispose();
    });
  });

  group('card', () {
    const host = Host(id: 'h', label: 'Web', address: 'web.example.org', username: 'root');

    Future<void> pumpCard(WidgetTester tester, ServerStatusController c) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      await tester.pumpWidget(
        AppScope(
          vault: store,
          manager: sessions,
          child: MaterialApp(
            theme: AppTheme.build(BuiltInThemes.matteBlack),
            home: Scaffold(
              body: ServerStatusCard(host: host, controller: c),
            ),
          ),
        ),
      );
      await tester.pump();
      sessions.dispose();
    }

    testWidgets('shows each number with a label', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = ServerStatusController((_) async => linuxOutput);
      await c.refresh();
      await pumpCard(tester, c);
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('45 %'), findsOneWidget);
      expect(find.text('1.9 GB of 7.6 GB'), findsOneWidget);
      expect(find.text('50.0 GB of 100 GB'), findsOneWidget);
      expect(find.text('0.52  0.41  0.30'), findsOneWidget);
      expect(find.text('3 days 2 h'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^CPU: 45 %, 45 percent$')), findsOneWidget);
      semantics.dispose();
      c.dispose();
    });

    testWidgets('explains when the server is not Linux', (tester) async {
      final c = ServerStatusController((_) async => 'unsupported');
      await c.refresh();
      await pumpCard(tester, c);
      expect(find.textContaining('not available'), findsOneWidget);
      c.dispose();
    });

    testWidgets('the host menu offers the status page', (tester) async {
      final store = await VaultStore.open(MemoryBackend());
      final sessions = SessionManager(store);
      await tester.pumpWidget(AppScope(
        vault: store,
        manager: sessions,
        child: MaterialApp(theme: AppTheme.build(BuiltInThemes.matteBlack), home: const Scaffold(body: HostTile(host: host))),
      ));
      await tester.tap(find.byTooltip('Actions for Web'));
      await tester.pumpAndSettle();
      expect(find.text('Server status'), findsOneWidget);
      sessions.dispose();
    });
  });
}
