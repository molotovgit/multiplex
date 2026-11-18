import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/herd_controller.dart';
import 'package:multiplex/sessions/herd_hub.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/agents.dart';
import 'package:multiplex/src/rust/api/herd_types.dart';
import 'package:multiplex/src/rust/api/ssh.dart';

/// A connection that is up and does nothing.
class _Ssh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Sessions extends SessionManager {
  _Sessions(super.store);

  final List<LiveSession> open = [];

  @override
  List<LiveSession> get sessions => open;

  void changed() => notifyListeners();
}

/// One computer's herdr, fed by hand; it counts who listens.
class _Herd implements HerdLink {
  _Herd(this.now);

  HerdState now;
  final told = StreamController<HerdState>.broadcast();
  var listening = 0;

  void tell(HerdState next) {
    now = next;
    told.add(next);
  }

  @override
  Future<HerdState> state() async => now;

  @override
  Future<(Stream<HerdState>, void Function())> watch() async {
    listening++;
    return (told.stream, () => listening--);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

HerdAgent _agent(String pane, AgentStatus status, String title) =>
    HerdAgent(session: 'default', workspace: 'api', tab: '1', pane: pane, name: 'Claude', status: status, title: title, folder: 'api');

HerdState _state(List<HerdAgent> agents) =>
    HerdState(available: true, sessions: const [], inbox: agents, waiting: agents.where((a) => a.status == AgentStatus.blocked).length);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const desk = Host(id: 'c', label: 'Desk', address: 'desk', computer: true);
  const laptop = Host(id: 'l', label: 'Laptop', address: 'laptop', computer: true);
  const server = Host(id: 's', label: 'Web server', address: 'web');

  late VaultStore store;
  late _Sessions sessions;
  late Map<String, _Herd> herds;
  late HerdHub hub;

  LiveSession connect(Host host) {
    final session = LiveSession(id: 's-${host.id}', host: host, ssh: _Ssh());
    sessions.open.add(session);
    sessions.changed();
    return session;
  }

  setUp(() async {
    store = await VaultStore.open(MemoryBackend());
    sessions = _Sessions(store);
    herds = {
      'c': _Herd(_state([_agent('w1:p1', AgentStatus.working, 'Refactor'), _agent('w1:p2', AgentStatus.done, 'Tests fixed')])),
      'l': _Herd(_state([_agent('w1:p1', AgentStatus.blocked, 'Allow this?'), _agent('w1:p3', AgentStatus.idle, 'Nothing to do')])),
      's': _Herd(_state([_agent('w1:p1', AgentStatus.blocked, 'A server is not asked')])),
    };
    hub = HerdHub(sessions, link: (session) => herds[session.host.id]!);
  });

  tearDown(() async {
    hub.dispose();
    sessions.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 450));
  });

  test('the agents that want the owner, from every connected computer: waiting first, then done', () async {
    expect(hub.wanting, isEmpty);
    connect(desk);
    connect(laptop);
    connect(server);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hub.wanting.map((one) => '${one.host.label}: ${one.agent.title}'), ['Laptop: Allow this?', 'Desk: Tests fixed']);
    expect(hub.waitingOn('l'), 1);
    expect(hub.waitingOn('c'), 0);
    expect(herds['s']!.listening, 0, reason: 'a plain server has no herd');
    // It follows each computer as that computer tells.
    var told = 0;
    hub.addListener(() => told++);
    herds['c']!.tell(_state([_agent('w1:p1', AgentStatus.blocked, 'Refactor: which name?')]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(told, greaterThan(0));
    expect(hub.wanting.map((one) => '${one.host.label}: ${one.agent.title}'), ['Desk: Refactor: which name?', 'Laptop: Allow this?']);
    expect(hub.waitingOn('c'), 1);
  });

  test('a computer that disconnects takes its agents with it, and its herd stops listening', () async {
    final session = connect(desk);
    connect(laptop);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(herds['c']!.listening, 1);
    final kept = hub.herdOf('c');
    expect(kept, isNotNull, reason: 'the same herd the Agents screen uses');
    sessions.open.remove(session);
    sessions.changed();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(herds['c']!.listening, 0);
    expect(hub.herdOf('c'), isNull);
    expect(hub.wanting.map((one) => one.host.label), ['Laptop']);
    // Connected again: a new herd, not the one that ended.
    connect(desk);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hub.herdOf('c'), isNot(same(kept)));
    expect(herds['c']!.listening, 1);
  });

  test('out of sight nothing is listened to; back in front it is, and what was known is still shown meanwhile', () async {
    connect(laptop);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(herds['l']!.listening, 1);
    final kept = hub.herdOf('l');
    hub.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(herds['l']!.listening, 0);
    expect(hub.wanting.single.agent.title, 'Allow this?');
    // A computer that connects meanwhile (the link does that) waits too.
    connect(desk);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(herds['c']!.listening, 0);
    hub.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(herds['l']!.listening, 1);
    expect(herds['c']!.listening, 1);
    expect(hub.herdOf('l'), same(kept), reason: 'an open Agents screen keeps working with it');
    expect(hub.wanting.map((one) => one.host.label), ['Laptop', 'Desk']);
  });
}
