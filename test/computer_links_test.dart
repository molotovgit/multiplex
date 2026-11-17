import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/computer_links.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/share.dart';
import 'package:multiplex/src/rust/api/ssh.dart';

/// A connection that is always up and does nothing.
class _Ssh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A computer that writes down what the phone asked of it.
class _Computer implements ShareChannel {
  final events = StreamController<ShareEvent>.broadcast();
  final log = <String>[];
  String? linkedAs;
  bool stopped = false;
  bool failFetch = false;

  @override
  Future<(Stream<ShareEvent>, void Function())> link(String phone) async {
    linkedAs = phone;
    return (events.stream, () => stopped = true);
  }

  @override
  Future<String> fetch(ShareEvent_File file) async {
    if (failFetch) throw Exception('the network dropped');
    log.add('fetch ${file.name}');
    return '/phone/downloads/${file.name}';
  }

  @override
  Future<void> done(String id) async => log.add('done $id');

  @override
  Future<void> copy(String text) async => log.add('copy $text');
}

/// Sessions, without connecting anywhere.
class _Sessions extends SessionManager {
  _Sessions(super.store);

  final List<LiveSession> open = [];

  @override
  List<LiveSession> get sessions => open;

  void changed() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VaultStore store;
  late _Sessions sessions;
  late _Computer computer;
  late ComputerLinks links;
  late List<String> notices;
  String? phoneClipboard;
  const desk = Host(id: 'c', label: 'Desk', address: 'desk', computer: true, pairedAs: 'My phone');

  Future<LiveSession> connect({Host host = desk}) async {
    final session = LiveSession(id: 's-${host.id}', host: host, ssh: _Ssh());
    sessions.open.add(session);
    sessions.changed();
    await Future<void>.delayed(Duration.zero);
    return session;
  }

  setUp(() async {
    store = await VaultStore.open(MemoryBackend());
    store.saveHost(desk);
    sessions = _Sessions(store);
    computer = _Computer();
    notices = [];
    phoneClipboard = 'on the phone already';
    links = ComputerLinks(
      sessions,
      store,
      channel: (_) => computer,
      notify: (title, body) async => notices.add('$title | $body'),
      readClipboard: () async => phoneClipboard,
      writeClipboard: (text) async => phoneClipboard = text,
    );
  });

  tearDown(() async {
    links.dispose();
    sessions.dispose();
    // Let the store's delayed save run.
    await Future<void>.delayed(const Duration(milliseconds: 450));
  });

  test('a connected computer is linked under the name the phone paired as; a plain server is not', () async {
    await connect(
      host: const Host(id: 'x', label: 'Web server', address: 'web'),
    );
    expect(computer.linkedAs, isNull);
    await connect();
    expect(computer.linkedAs, 'My phone');
  });

  test('a waiting file is fetched, acknowledged and announced', () async {
    await connect();
    computer.events.add(ShareEvent.file(id: '00aa', name: 'notes.pdf', size: BigInt.from(12), path: '/home/me/notes.pdf'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['fetch notes.pdf', 'done 00aa']);
    expect(notices, ['notes.pdf from Desk | Saved in Multiplex downloads']);
    expect(links.received.single.path, '/phone/downloads/notes.pdf');
  });

  test('a file that could not be fetched stays with the computer', () async {
    await connect();
    computer.failFetch = true;
    computer.events.add(ShareEvent.file(id: '00bb', name: 'big.iso', size: BigInt.from(1), path: '/x'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, isEmpty, reason: 'not acknowledged, so it is offered again next time');
    expect(notices, isEmpty);
  });

  test('the computer\'s clipboard lands on the phone, once', () async {
    await connect();
    computer.events.add(const ShareEvent.clip(text: 'copied at the desk'));
    await Future<void>.delayed(Duration.zero);
    expect(phoneClipboard, 'copied at the desk');
    // Coming back to the app does not send the same text straight back.
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, isEmpty);
  });

  test('what was copied on the phone goes over when the app comes back in front', () async {
    await connect();
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, isEmpty, reason: 'what was there before the link is not news');
    phoneClipboard = 'copied on the phone';
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['copy copied on the phone']);
  });

  test('with clipboard sharing off nothing moves by itself, but a request still does', () async {
    store.saveHost(desk.copyWith(shareClipboard: false));
    final session = await connect();
    computer.events.add(const ShareEvent.clip(text: 'from the desk'));
    phoneClipboard = 'private';
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(phoneClipboard, 'private');
    expect(computer.log, isEmpty);
    expect(await links.sendClipboardTo(session), isTrue);
    expect(computer.log, ['copy private']);
  });

  test('the link ends with the connection', () async {
    await connect();
    sessions.open.clear();
    sessions.changed();
    expect(computer.stopped, isTrue);
  });
}
