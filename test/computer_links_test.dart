import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/platform/agent_notices.dart';
import 'package:multiplex/platform/phone_bridge.dart';
import 'package:multiplex/platform/phone_hands.dart';
import 'package:multiplex/sessions/computer_links.dart';
import 'package:multiplex/sessions/herd_controller.dart';
import 'package:multiplex/sessions/phone_outbox.dart';
import 'package:multiplex/sessions/session_manager.dart';
import 'package:multiplex/src/rust/api/herd_types.dart';
import 'package:multiplex/src/rust/api/share.dart';
import 'package:multiplex/src/rust/api/ssh.dart';
import 'package:multiplex/update/update_platform.dart';

/// A connection that is always up and does nothing.
class _Ssh implements SshSession {
  @override
  bool isConnected() => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The phone as a keyboard, written down.
class _Hands implements PhoneHands {
  final sent = <String>[];
  String? problem;

  @override
  Future<String?> send(Uint8List keys, Uint8List pointer) async {
    if (problem != null) return problem;
    sent.add('${keys.length} bytes of keys, ${pointer.length} of pointer');
    return null;
  }

  @override
  Future<({String? path, String? problem})> look() async => (path: null, problem: 'The camera is not looking at anything.');
}

/// The phone's notifications about agents, written down.
class _AgentNotices implements AgentNotices {
  final posted = <AgentNotice>[];
  final withdrawn = <String>[];

  /// What the app does with an answer given in a notification.
  Future<String?> Function(AgentAnswer answer)? answer;

  @override
  Future<void> post(AgentNotice notice) async => posted.add(notice);

  @override
  Future<void> withdraw(String tag) async => withdrawn.add(tag);

  @override
  void listen(Future<String?> Function(AgentAnswer answer) onAnswer) => answer = onAnswer;

  @override
  void stop() => answer = null;
}

/// A computer's session server that writes down the answers it is given.
class _AnsweredHerd implements HerdLink {
  final log = <String>[];
  Object? refuses;

  @override
  Future<void> answerChoice(String session, String pane, String mark, String choice) async {
    if (refuses != null) throw refuses!;
    log.add('choice $session $pane [$mark] $choice');
  }

  @override
  Future<void> answerText(String session, String pane, String mark, String text) async {
    if (refuses != null) throw refuses!;
    log.add('text $session $pane [$mark] $text');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

  /// Where a fetched file "lands" on the phone, when a test needs a real one.
  String? downloadTo;

  @override
  Future<String> fetch(ShareEvent_File file) async {
    if (failFetch) throw Exception('the network dropped');
    log.add('fetch ${file.name}');
    return downloadTo ?? '/phone/downloads/${file.name}';
  }

  @override
  Future<void> done(String id) async => log.add('done $id');

  @override
  Future<void> copy(String text) async => log.add('copy $text');

  /// The picture on this stand-in computer's clipboard.
  ClipboardPicture? picture;

  @override
  Future<ClipboardPicture?> pastePicture() async {
    log.add('paste picture');
    return picture;
  }

  @override
  Future<void> copyPicture(ClipboardPicture picture) async => log.add('copy picture ${picture.kind} ${picture.bytes}');

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

/// The phone's updater: says whether an app file is a newer Multiplex.
class _Updater implements UpdatePlatform {
  _Updater(this.folder);

  final Directory folder;
  String? problem;
  bool allowed = true;
  final installed_ = <String>[];
  int permissionOpened = 0;

  @override
  Future<Directory> downloadDir() async => folder..createSync(recursive: true);

  @override
  Future<ApkReport> checkApk(String path) async => ApkReport(problem);

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallPermission() async => permissionOpened++;

  @override
  Future<void> install(String path) async => installed_.add(path);

  @override
  Future<InstalledApp?> installed() async => null;
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
  ClipboardPicture? phonePicture;
  late Directory temp;
  late PhoneOutbox outbox;
  late _Phone phone;
  late _Updater updater;
  late _AgentNotices agentNotices;
  late _Hands hands;
  late _AnsweredHerd herd;
  final dialled = <String>[];
  var reachable = false;
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
    agentNotices = _AgentNotices();
    hands = _Hands();
    herd = _AnsweredHerd();
    phoneClipboard = 'on the phone already';
    phonePicture = null;
    temp = Directory.systemTemp.createTempSync('outbox-test');
    outbox = PhoneOutbox(root: () async => Directory('${temp.path}/outbox'));
    phone = _Phone();
    updater = _Updater(Directory('${temp.path}/updates'));
    asked.clear();
    dialled.clear();
    reachable = false;
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
      agentNotices: agentNotices,
      hands: hands,
      herd: (_) => herd,
      answerWithin: const Duration(milliseconds: 400),
      readClipboard: () async => phoneClipboard,
      writeClipboard: (text) async => phoneClipboard = text,
      readPicture: () async => phonePicture,
      writePicture: (picture) async => phonePicture = picture,
      markOf: (bytes) => bytes.join('.'),
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
      updates: updater,
      connect: (host) async {
        dialled.add(host.title);
        if (!reachable) throw Exception('out of reach');
        await connect(host: host);
      },
      retryAfter: const Duration(milliseconds: 120),
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

  test('a link that starts before the clipboard can be read sends nothing old to the computer', () async {
    // Android only lets the app in front read the clipboard.
    phoneClipboard = null;
    await connect();
    phoneClipboard = 'copied yesterday';
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, isEmpty, reason: 'the first look only notes what is there');
    phoneClipboard = 'copied just now';
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['copy copied just now']);
  });

  test('a picture copied at the computer is fetched onto the phone, once', () async {
    await connect();
    final screenshot = ClipboardPicture('png', Uint8List.fromList([1, 2, 3]));
    computer.picture = screenshot;
    // The computer only says that there is one; the phone fetches it.
    computer.events.add(ShareEvent.picture(kind: 'png', size: BigInt.from(3), mark: '1.2.3'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['paste picture']);
    expect(phonePicture?.bytes, [1, 2, 3]);
    expect(phonePicture?.kind, 'png');
    // Said again (the clipboard was touched, same picture): not fetched again.
    computer.events.add(ShareEvent.picture(kind: 'png', size: BigInt.from(3), mark: '1.2.3'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['paste picture']);
    // Coming back to the app does not send it straight back.
    phoneClipboard = null;
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['paste picture']);
  });

  test('the same picture copied again after something else counts as new', () async {
    await connect();
    computer.picture = ClipboardPicture('png', Uint8List.fromList([1, 2, 3]));
    computer.events.add(ShareEvent.picture(kind: 'png', size: BigInt.from(3), mark: '1.2.3'));
    await Future<void>.delayed(Duration.zero);
    // Text in between replaces it on the phone.
    computer.events.add(const ShareEvent.clip(text: 'words in between'));
    await Future<void>.delayed(Duration.zero);
    expect(phoneClipboard, 'words in between');
    phonePicture = null;
    // The same picture again: it has to come over again.
    computer.events.add(ShareEvent.picture(kind: 'png', size: BigInt.from(3), mark: '1.2.3'));
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['paste picture', 'paste picture']);
    expect(phonePicture?.bytes, [1, 2, 3]);
    // And the same words again after that picture.
    phoneClipboard = null;
    computer.events.add(const ShareEvent.clip(text: 'words in between'));
    await Future<void>.delayed(Duration.zero);
    expect(phoneClipboard, 'words in between');
  });

  test('a picture that was replaced on the computer before it could be fetched is let go', () async {
    await connect();
    computer.picture = ClipboardPicture('png', Uint8List.fromList([9, 9]));
    computer.events.add(ShareEvent.picture(kind: 'png', size: BigInt.from(3), mark: '1.2.3'));
    await Future<void>.delayed(Duration.zero);
    expect(phonePicture, isNull, reason: 'what came is not the picture that was announced');
  });

  test('a picture copied on the phone goes over when the app comes back in front', () async {
    await connect();
    // A picture, so no text.
    phoneClipboard = null;
    phonePicture = ClipboardPicture('jpeg', Uint8List.fromList([4, 5]));
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['copy picture jpeg [4, 5]']);
    // The same picture is not sent twice.
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['copy picture jpeg [4, 5]']);
    // Text copied afterwards goes as text.
    phoneClipboard = 'and now words';
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, ['copy picture jpeg [4, 5]', 'copy and now words']);
  });

  test('a picture that was on the phone before the link is not news', () async {
    phoneClipboard = null;
    phonePicture = ClipboardPicture('png', Uint8List.fromList([7]));
    await connect();
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, isEmpty);
  });

  test('with clipboard sharing off pictures stay where they are too', () async {
    store.saveHost(desk.copyWith(shareClipboard: false));
    final session = await connect();
    computer.picture = ClipboardPicture('png', Uint8List.fromList([1]));
    computer.events.add(ShareEvent.picture(kind: 'png', size: BigInt.from(1), mark: '1'));
    phoneClipboard = null;
    phonePicture = ClipboardPicture('png', Uint8List.fromList([2]));
    links.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(computer.log, isEmpty);
    expect(phonePicture?.bytes, [2]);
    // Asked for by hand, it still goes.
    expect(await links.sendClipboardTo(session), isTrue);
    expect(computer.log, ['copy picture png [2]']);
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

  test('typing through the phone: only for a computer it is switched on for, and every ask is answered', () async {
    await connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final keys = Uint8List.fromList([2, 0, 0x0b, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    final none = Uint8List(0);
    // Off, as it is until the owner says otherwise: nothing is typed, and the computer hears why.
    computer.events.add(ShareEvent.hands(id: 'aa01', keys: keys, pointer: none, look: false));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hands.sent, isEmpty);
    expect(computer.log.single, startsWith('approval aa01: no: Typing through this phone is switched off for Desk.'));

    computer.log.clear();
    store.saveHost(store.host('c')!.copyWith(allowHands: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    computer.events.add(ShareEvent.hands(id: 'aa02', keys: keys, pointer: Uint8List.fromList([1, 0, 0, 0, 0, 0]), look: false));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hands.sent, ['16 bytes of keys, 6 of pointer']);
    expect(computer.log, ['approval aa02: ok']);
    // No device is connected: said to whoever asked.
    computer.log.clear();
    hands.problem = 'The phone is not connected to a device as its keyboard.';
    computer.events.add(ShareEvent.hands(id: 'aa03', keys: keys, pointer: none, look: false));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(computer.log, ['approval aa03: no: The phone is not connected to a device as its keyboard.']);
    // A look: the picture's place, or why there is none.
    computer.log.clear();
    computer.events.add(ShareEvent.hands(id: 'aa04', keys: none, pointer: none, look: true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(computer.log, ['approval aa04: no: The camera is not looking at anything.']);
  });

  group('coding agents', () {
    const asked = HerdAsked(
      question: 'Bash command\n\nmake test\n\nDo you want to proceed?',
      choices: [
        HerdChoice(key: '1', label: 'Yes'),
        HerdChoice(key: '2', label: "Yes, and don't ask again for make commands in this folder"),
        HerdChoice(key: '3', label: 'No, and tell Claude what to do differently'),
      ],
      mark: '0123456789abcdef',
    );
    const waits = ShareEvent.agent(name: 'Claude', title: 'Fix the tests', workspace: 'api', waiting: true, session: 'default', pane: 'w1:p1', asked: asked);

    test('one that waits on a choice is announced with its question, and its choices to press', () async {
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(waits);
      await Future<void>.delayed(Duration.zero);
      final notice = agentNotices.posted.single;
      expect(notice.title, 'Claude needs you');
      expect(notice.summary, 'Bash command · make test · Do you want to proceed?');
      expect(notice.body, 'Bash command\n\nmake test\n\nDo you want to proceed?\n\nFix the tests · api · Desk');
      expect(notice.choices.map((c) => '${c.key}=${c.label}'), [
        '1=Yes',
        "2=Yes, and don't ask again for make commands in this folder",
        '3=No, and tell Claude what to do differently',
      ]);
      expect(notice.reply, isFalse, reason: 'it wants one of its choices, not words');
      expect((notice.place.tag, notice.place.mark), ('c/default/w1:p1', '0123456789abcdef'));
      expect(AgentNotice.onButton(notice.choices[1].label), "Yes, and don't ask again fo…");
      expect(notices, isEmpty, reason: 'not told twice');
    });

    test('one that is done, or asks in its own words, can be answered in words', () async {
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(const ShareEvent.agent(name: 'codex', title: '', workspace: '', waiting: false, session: 'default', pane: 'w1:p2'));
      computer.events.add(const ShareEvent.agent(name: 'Claude', title: 'Which name?', workspace: 'api', waiting: true, session: 'default', pane: 'w1:p1'));
      await Future<void>.delayed(Duration.zero);
      expect(
        agentNotices.posted.map((n) => '${n.title} | ${n.summary} | ${n.body} | reply ${n.reply} | ${n.choices.length} choices | mark "${n.place.mark}"'),
        [
          'codex is done | Desk | Desk | reply true | 0 choices | mark ""',
          'Claude needs you | Which name? · api · Desk | Which name? · api · Desk | reply true | 0 choices | mark ""',
        ],
      );
      expect(agentNotices.posted.map((n) => n.waiting), [false, true], reason: 'only one that waits comes up on top of the screen');
    });

    test('one the computer could not place is announced as before, with nothing to press', () async {
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(const ShareEvent.agent(name: 'Claude', title: 'Fix the tests', workspace: 'api', waiting: true, session: '', pane: ''));
      await Future<void>.delayed(Duration.zero);
      expect(notices, ['Claude needs you | Fix the tests · api · Desk']);
      expect(agentNotices.posted, isEmpty);
    });

    test('one that no longer waits has its notification taken back', () async {
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(waits);
      computer.events.add(const ShareEvent.settled(session: 'default', pane: 'w1:p1'));
      await Future<void>.delayed(Duration.zero);
      expect(agentNotices.withdrawn, ['c/default/w1:p1']);
    });

    test('with the app lock on, an answer waits for the app: nothing to press or type', () async {
      store.updateSettings(store.settings.copyWith(appLock: true));
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      computer.events.add(waits);
      computer.events.add(const ShareEvent.agent(name: 'codex', title: '', workspace: '', waiting: false, session: 'default', pane: 'w1:p2'));
      await Future<void>.delayed(Duration.zero);
      expect(agentNotices.posted.map((n) => (n.choices.length, n.reply)), [(0, false), (0, false)]);
      expect(agentNotices.posted.first.body, contains('make test'), reason: 'what it asks is still said');
      // And one pressed all the same (a notification from before the lock was turned on) is not sent.
      const place = AgentPlace(hostId: 'c', session: 'default', pane: 'w1:p1', mark: '0123456789abcdef');
      expect(await agentNotices.answer!(const AgentAnswer(place: place, choice: '1')), 'Open Multiplex to answer.');
      expect(herd.log, isEmpty);
    });

    test('an answer given in the notification goes to the computer, which says if it was too late', () async {
      await connect();
      const place = AgentPlace(hostId: 'c', session: 'default', pane: 'w1:p1', mark: '0123456789abcdef');
      expect(await agentNotices.answer!(const AgentAnswer(place: place, choice: '3')), isNull);
      expect(herd.log, ['choice default w1:p1 [0123456789abcdef] 3']);
      // Words, for one that asked in words or finished.
      const other = AgentPlace(hostId: 'c', session: 'default', pane: 'w1:p2');
      expect(await agentNotices.answer!(const AgentAnswer(place: other, text: '  now run the linter  ')), isNull);
      expect(herd.log.last, 'text default w1:p2 [] now run the linter');
      // The agent has moved on: the computer sent nothing, and its words reach the owner.
      herd.refuses = Exception('That is no longer what it asks. Nothing was sent.');
      expect(await agentNotices.answer!(const AgentAnswer(place: place, choice: '1')), 'That is no longer what it asks. Nothing was sent.');
      // Nothing to send; a computer that is no longer paired.
      herd.log.clear();
      expect(await agentNotices.answer!(const AgentAnswer(place: other, text: '   ')), 'There was nothing to send.');
      expect(
        await agentNotices.answer!(
          const AgentAnswer(
            place: AgentPlace(hostId: 'gone', session: 'default', pane: 'w1:p1'),
            choice: '1',
          ),
        ),
        'That computer is no longer paired with this phone.',
      );
      expect(herd.log, isEmpty);
    });

    test('an answer given while the computer is not connected waits for the link, and says so if there is none', () async {
      const place = AgentPlace(hostId: 'c', session: 'default', pane: 'w1:p1', mark: '0123456789abcdef');
      // Out of reach: said, after the link was tried.
      expect(await agentNotices.answer!(const AgentAnswer(place: place, choice: '1')), 'Desk is not connected. Open Multiplex to answer.');
      expect(dialled, contains('Desk'));
      expect(herd.log, isEmpty);
      // In reach (the app had only just been started for this): it connects, and the answer goes.
      reachable = true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(await agentNotices.answer!(const AgentAnswer(place: place, choice: '1')), isNull);
      expect(herd.log, ['choice default w1:p1 [0123456789abcdef] 1']);
    });
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

  group('a newer app from the computer', () {
    /// A computer that really leaves a file on the phone.
    Future<void> receive(String name) async {
      File('${temp.path}/$name').writeAsStringSync('app');
      computer.downloadTo = '${temp.path}/$name';
      computer.events.add(ShareEvent.file(id: '00ee', name: name, size: BigInt.from(3), path: '/home/me/$name'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    test('a newer Multiplex with the same signature is offered and can be installed', () async {
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await receive('multiplex.apk');
      expect(links.newerApp?.from, 'Desk');
      expect(notices.last, startsWith('A newer Multiplex from Desk'));
      expect(await links.installNewerApp(), isTrue);
      expect(updater.installed_.single, endsWith('from-computer.apk'));
    });

    test('another app, an older one or a differently signed one is just a file', () async {
      updater.problem = 'otherSigner';
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await receive('something.apk');
      expect(links.newerApp, isNull);
      expect(links.received.single.name, 'something.apk');
      expect(Directory('${temp.path}/updates').listSync(), isEmpty, reason: 'the copy made for checking is removed');
    });

    test('without the permission, Android\'s page for it opens instead', () async {
      updater.allowed = false;
      await connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await receive('multiplex.apk');
      expect(await links.installNewerApp(), isFalse);
      expect(updater.permissionOpened, 1);
      expect(updater.installed_, isEmpty);
    });
  });

  group('staying connected', () {
    test('a paired computer is linked by itself; one out of reach is tried again later, not at once', () async {
      // The first try comes two seconds after start.
      await Future<void>.delayed(const Duration(milliseconds: 2050));
      expect(dialled, ['Desk']);
      expect(computer.linkedAs, isNull, reason: 'it was out of reach');
      // A change in the saved data looks again, but not before the wait is over.
      store.saveHost(const Host(id: 'x', label: 'Web server', address: 'web'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(dialled, ['Desk']);
      // Once the wait is over it is tried again by itself: nothing has to
      // happen on the phone for that.
      reachable = true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(dialled, ['Desk', 'Desk']);
      expect(computer.linkedAs, 'My phone', reason: 'connected and linked with nothing tapped');
      // Connected: nothing more to do, and plain servers are never dialled.
      store.saveHost(const Host(id: 'z', label: 'Third', address: 'third'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(dialled, ['Desk', 'Desk']);
    });

    test('a computer out of reach is tried again soon at first, then less and less often', () {
      const longest = Duration(seconds: 45);
      expect([for (var failures = 1; failures <= 6; failures++) ComputerLinks.waitAfter(failures, longest).inSeconds], [3, 6, 12, 24, 45, 45]);
      // Never longer than the longest wait, however short that is, or however often it failed.
      expect(ComputerLinks.waitAfter(1, const Duration(seconds: 1)), const Duration(seconds: 1));
      expect(ComputerLinks.waitAfter(500, longest), longest);
      // One that was reached and then went is not dialled at once.
      expect(ComputerLinks.waitAfter(0, longest), longest);
    });

    test('switched off, or after the owner closed the connection, it is left alone until they come back', () async {
      reachable = true;
      store.saveHost(desk.copyWith(keyId: () => 'k', stayConnected: false));
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(dialled, isEmpty, reason: 'switched off for this computer');

      store.saveHost(desk.copyWith(keyId: () => 'k', stayConnected: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(dialled, ['Desk']);
      // The owner disconnects on purpose.
      sessions.open.clear();
      sessions.changed();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      store.saveHost(const Host(id: 'x', label: 'Web server', address: 'web'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(dialled, ['Desk'], reason: 'not dialled again behind their back');
      // They open the app again.
      links.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(dialled, ['Desk', 'Desk']);
    });
  });

  test('the link ends with the connection', () async {
    await connect();
    sessions.open.clear();
    sessions.changed();
    expect(computer.stopped, isTrue);
  });
}
