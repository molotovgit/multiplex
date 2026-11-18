import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/app_life.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/ssh.dart';

/// A connection that is always up and does nothing.
class _Ssh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A session manager that only keeps a list.
class _Sessions extends SessionManager {
  _Sessions(super.store);

  final open = <LiveSession>[];
  final closed = <String>[];

  @override
  List<LiveSession> get sessions => List.unmodifiable(open);

  @override
  Future<void> disconnect(LiveSession session) async {
    open.remove(session);
    closed.add(session.host.title);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('multiplex/life');
  const desk = Host(id: 'c', label: 'Desk', address: 'desk', computer: true);
  const laptop = Host(id: 'l', label: 'Laptop', address: 'laptop', computer: true, stayConnected: false);
  const server = Host(id: 's', label: 'Web server', address: 'web.example.com');

  late VaultStore store;
  late _Sessions sessions;
  late List<Object?> told;

  setUp(() async {
    store = await VaultStore.open(MemoryBackend());
    sessions = _Sessions(store);
    told = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setLinks') told.add(call.arguments);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    addTearDown(sessions.dispose);
  });

  LiveSession session(Host host) => LiveSession(id: host.id, host: host, ssh: _Ssh());

  test('only paired computers set to stay connected keep their link', () {
    expect(AppLife.keeps(desk), isTrue);
    expect(AppLife.keeps(laptop), isFalse, reason: 'its owner switched that off');
    expect(AppLife.keeps(server), isFalse, reason: 'a server is not a paired computer');
  });

  test('swiping the app away closes what was there for the screen, and keeps the links', () async {
    var screensClosed = 0;
    final life = AppLife(sessions, store, closeScreens: () => screensClosed++);
    addTearDown(life.dispose);
    sessions.open.addAll([session(desk), session(laptop), session(server)]);
    // As Android says it.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('taskRemoved')),
      (_) {},
    );
    expect(screensClosed, 1);
    expect(sessions.closed, ['Laptop', 'Web server']);
    expect(sessions.sessions.map((s) => s.host.title), ['Desk']);
  });

  test('Android is told whether there is anything to start with the phone for', () async {
    final life = AppLife(sessions, store);
    addTearDown(life.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(told, [false], reason: 'no computer yet');
    store.saveHost(server);
    store.saveHost(laptop);
    await Future<void>.delayed(Duration.zero);
    expect(told, [false], reason: 'still nothing that stays connected, and nothing said twice');
    store.saveHost(desk);
    await Future<void>.delayed(Duration.zero);
    expect(told, [false, true]);
    store.saveHost(desk.copyWith(stayConnected: false));
    await Future<void>.delayed(Duration.zero);
    expect(told, [false, true, false]);
    // Let the store's delayed save run, so no timer outlives the test.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
}
