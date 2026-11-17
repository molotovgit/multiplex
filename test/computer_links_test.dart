import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/platform/phone_bridge.dart';
import 'package:multiplex/sessions/computer_links.dart';
import 'package:multiplex/sessions/phone_outbox.dart';
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

  /// What the phone said about its battery (kept apart: it says so by itself).
  final statuses = <String>[];
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

  @override
  Future<void> status(String phone, {required int battery, required bool charging}) async => statuses.add('$phone: $battery%${charging ? ' charging' : ''}');

  @override
  Future<void> notice(String phone, PhoneNotification notification) async => log.add('notice ${notification.app}: ${notification.title}');

  @override
  Future<void> call(String phone, {required bool active}) async => log.add('call ${active ? 'started' : 'ended'}');

  @override
  Future<void> dnd({required bool on}) async => log.add('quiet ${on ? 'on' : 'off'}');

  @override
  Future<void> approved(String id, String answer) async => log.add('approval $id: $answer');

  /// Names that do not make it across.
  final failing = <String>{};

  @override
  Future<List<WaitingFile>> send(List<WaitingFile> files, {required String phone}) async {
    log.add('send from $phone: ${files.map((f) => f.name).join(', ')}');
    return [
      for (final f in files)
        if (!failing.contains(f.name)) f,
    ];
  }
}

/// The phone itself: its battery, its ringer, its notifications.
class _Phone extends PhoneBridge {
  _Phone();

  final posted = StreamController<PhoneNotification>.broadcast();
  final changed = StreamController<({bool? call, bool? dnd})>.broadcast();
  final rang = <int>[];

  @override
  Future<void> ring(int seconds) async => rang.add(seconds);

  final texts = <String>[];

  /// Why Android would not send, if it would not.
  String? smsProblem;

  @override
  Future<String?> sendSms(String to, String text) async {
    if (smsProblem == null) texts.add('$to: $text');
    return smsProblem;
  }

  @override
  Future<({int level, bool charging})?> battery() async => (level: 82, charging: true);

  @override
  Stream<PhoneNotification> notifications() => posted.stream;

  @override
  Stream<({bool? call, bool? dnd})> changes() => changed.stream;
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
  late Directory temp;
  late PhoneOutbox outbox;
  late _Phone phone;
  final asked = <String>[];
  var fingerprintOk = true;
  var inFront = true;
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
    temp = Directory.systemTemp.createTempSync('outbox-test');
    outbox = PhoneOutbox(root: () async => Directory('${temp.path}/outbox'));
    phone = _Phone();
    asked.clear();
    fingerprintOk = true;
    inFront = true;
    store.saveKey(
      StoredKey(
        id: 'k',
        name: 'This phone',
        privatePem: 'PRIVATE',
        publicOpenssh: 'ssh-ed25519 AAAA',
        fingerprint: 'SHA256:x',
        algorithm: 'ed25519',
        passphrase: null,
        encrypted: false,
        createdAt: DateTime(2026),
      ),
    );
    store.saveHost(desk.copyWith(keyId: () => 'k'));
    links = ComputerLinks(
      sessions,
      store,
      channel: (_) => computer,
      notify: (title, body) async => notices.add('$title | $body'),
      readClipboard: () async => phoneClipboard,
      writeClipboard: (text) async => phoneClipboard = text,
      outbox: outbox,
      phone: phone,
      confirm: (reason) async {
        asked.add(reason);
        return fingerprintOk;
      },
      sign: (key, id, reason, challenge) => 'signed($id|$reason|$challenge|${key.length})',
      describeSigning: (key, data) => data == 'LOGIN' ? 'Log in as sam with this phone\'s key' : null,
      signRequest: (key, data) => 'sshsig($data)',
      appInFront: () => inFront,
    );
  });

  tearDown(() async {
    links.dispose();
    sessions.dispose();
    // Let the store's delayed save run.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    temp.deleteSync(recursive: true);
  });

  File shared(String name) => File('${temp.path}/$name')..writeAsStringSync('hello $name');

  test('files kept for an unreachable computer wait, in order, under names that do not clash', () async {
    final first = await outbox.add('c', name: 'photo.jpg', path: shared('photo.jpg').path);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The first was moved away, so the same name is free again.
    final second = await outbox.add('c', name: 'photo.jpg', path: shared('photo.jpg').path);
    expect(first.name, 'photo.jpg');
    expect(second.name, 'photo (1).jpg');
    expect(File('${temp.path}/photo.jpg').existsSync(), isFalse, reason: 'moved, not copied');
    expect((await outbox.waiting('c')).map((f) => f.name), ['photo.jpg', 'photo (1).jpg']);
    expect(await outbox.waiting('another computer'), isEmpty);
    await outbox.remove(first);
    expect((await outbox.waiting('c')).map((f) => f.name), ['photo (1).jpg']);
  });

  test('what waited on the phone goes when the computer connects; what fails keeps waiting', () async {
    await outbox.add('c', name: 'notes.txt', path: shared('notes.txt').path);
    await outbox.add('c', name: 'big.iso', path: shared('big.iso').path);
    computer.failing.add('big.iso');
    await connect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(computer.log.single, startsWith('send from My phone: '));
    expect(computer.log.single, allOf(contains('notes.txt'), contains('big.iso')));
    expect((await outbox.waiting('c')).map((f) => f.name), ['big.iso']);
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

  test('the computer hears the battery level, and can ring the phone', () async {
    await connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(computer.statuses, ['My phone: 82% charging']);
    computer.events.add(const ShareEvent.ring(seconds: 30));
    await Future<void>.delayed(Duration.zero);
    expect(phone.rang, [30]);
  });

  test('phone notifications go to the computer only when asked for, and not from muted apps', () async {
    await connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    computer.log.clear();
    phone.posted.add(const PhoneNotification(app: 'Messages', title: 'Sam', text: 'On my way'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, isEmpty, reason: 'off until switched on for this computer');
    expect(links.seenApps, {'Messages'});

    store.saveHost(desk.copyWith(mirrorNotifications: true, mutedApps: ['Games']));
    phone.posted.add(const PhoneNotification(app: 'Messages', title: 'Sam', text: 'Nearly there'));
    phone.posted.add(const PhoneNotification(app: 'Games', title: 'Come back!', text: 'Your crops are ready'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['notice Messages: Sam']);
  });

  test('a call pauses the computer; Do Not Disturb follows only when asked to', () async {
    await connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    phone.changed.add((call: true, dnd: null));
    phone.changed.add((call: false, dnd: null));
    phone.changed.add((call: null, dnd: true));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['call started', 'call ended'], reason: 'pausing for calls is on by default, quiet together is not');

    computer.log.clear();
    store.saveHost(desk.copyWith(syncDnd: true, pauseMediaOnCalls: false));
    phone.changed.add((call: true, dnd: null));
    phone.changed.add((call: null, dnd: true));
    phone.changed.add((call: null, dnd: false));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['quiet on', 'quiet off']);
  });

  test('a text message is sent only when this computer may, and it always hears the outcome', () async {
    await connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    computer.events.add(const ShareEvent.sms(to: '+15550100', text: 'On my way'));
    await Future<void>.delayed(Duration.zero);
    expect(phone.texts, isEmpty, reason: 'off until switched on for this computer');
    expect(computer.log, ['notice Messages: Not sent to +15550100']);

    computer.log.clear();
    store.saveHost(desk.copyWith(allowSms: true));
    computer.events.add(const ShareEvent.sms(to: '+15550100', text: 'On my way'));
    await Future<void>.delayed(Duration.zero);
    expect(phone.texts, ['+15550100: On my way']);
    expect(computer.log, ['notice Messages: Sent to +15550100']);

    computer.log.clear();
    phone.smsProblem = 'Android has not allowed Multiplex to send text messages.';
    computer.events.add(const ShareEvent.sms(to: '+15550100', text: 'Again'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['notice Messages: Not sent to +15550100']);
  });

  test('an agent that wants an answer, or is done, is announced on the phone', () async {
    await connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    computer.events.add(const ShareEvent.agent(name: 'Claude', title: 'Fix the tests', workspace: 'api', waiting: true));
    computer.events.add(const ShareEvent.agent(name: 'codex', title: '', workspace: '', waiting: false));
    await Future<void>.delayed(Duration.zero);
    expect(notices, ['Claude needs you | Fix the tests · api · Desk', 'codex is done | Desk']);
  });

  group('approving something for the computer', () {
    final ask = const ShareEvent.approve(id: '00aa', reason: 'sudo pacman -Syu', challenge: 'Yw==');

    test('a fingerprint gives a signed yes, for exactly what was shown', () async {
      await connect(host: desk.copyWith(keyId: () => 'k'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(ask);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asked, ['Approve on Desk: sudo pacman -Syu']);
      expect(computer.log, ['approval 00aa: signed(00aa|sudo pacman -Syu|Yw==|7)']);
    });

    test('a cancelled fingerprint is a no, and nothing is signed', () async {
      fingerprintOk = false;
      await connect(host: desk.copyWith(keyId: () => 'k'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(ask);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(computer.log, ['approval 00aa: no']);
    });

    test('with the app in the background a notification asks for it, and the prompt waits for the app', () async {
      inFront = false;
      await connect(host: desk.copyWith(keyId: () => 'k'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(ask);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notices, ['Desk asks for your approval | Open Multiplex to answer: sudo pacman -Syu']);
      expect(asked, isEmpty, reason: 'no prompt while the app is not on screen');
      expect(computer.log, isEmpty);
      inFront = true;
      links.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asked, ['Approve on Desk: sudo pacman -Syu']);
      expect(computer.log, ['approval 00aa: signed(00aa|sudo pacman -Syu|Yw==|7)']);
    });

    test('a computer without a key of this phone gets a no', () async {
      await connect(host: desk.copyWith(keyId: () => null));
      store.saveHost(desk.copyWith(keyId: () => null));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(ask);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asked, isEmpty);
      expect(computer.log, ['approval 00aa: no']);
    });
  });

  group('the phone\'s key, used from the computer', () {
    test('a login is shown as what it is and signed after a fingerprint', () async {
      await connect(host: desk.copyWith(keyId: () => 'k'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(const ShareEvent.sign(id: '00bb', data: 'LOGIN'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asked, ["Log in as sam with this phone's key (asked by Desk)"]);
      expect(computer.log, ['approval 00bb: sshsig(LOGIN)']);
    });

    test('what is not a login or an SSH signature is refused without asking', () async {
      await connect(host: desk.copyWith(keyId: () => 'k'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(const ShareEvent.sign(id: '00cc', data: 'SOMETHING ELSE'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asked, isEmpty);
      expect(computer.log, ['approval 00cc: no']);
    });

    test('a refused fingerprint signs nothing', () async {
      fingerprintOk = false;
      await connect(host: desk.copyWith(keyId: () => 'k'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(const ShareEvent.sign(id: '00dd', data: 'LOGIN'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(computer.log, ['approval 00dd: no']);
    });
  });

  test('the link ends with the connection', () async {
    await connect();
    sessions.open.clear();
    sessions.changed();
    expect(computer.stopped, isTrue);
  });
}
