export 'clipboard_picture.dart' show ClipboardPicture;

import 'clipboard_picture.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app/lock_gate.dart';
import '../data/models.dart';
import '../data/vault_store.dart';
import '../platform/agent_notices.dart';
import '../platform/phone_bridge.dart';
import '../platform/phone_hands.dart';
import '../src/rust/api/desk_types.dart';
import '../src/rust/api/herd_types.dart';
import '../src/rust/api/sftp_types.dart';
import '../src/rust/api/share.dart';
import '../ui/files/transfer_queue.dart';
import '../ui/files/transfer_tasks.dart';
import '../update/update_platform.dart';
import 'error_text.dart';
import 'herd_controller.dart';
import 'phone_outbox.dart';
import 'session_manager.dart';
import 'shell_launch.dart';

/// What a link needs from one connected computer. The real one is the
/// SSH connection (commands in the Rust core, files by SFTP); tests pass
/// a stand-in.
abstract class ShareChannel {
  /// What the computer has for this phone, and how to stop listening.
  Future<(Stream<ShareEvent>, void Function())> link(String phone);

  /// Downloads a waiting file; the answer is where it is on the phone.
  Future<String> fetch(ShareEvent_File file);

  /// The phone has the file: the computer forgets it.
  Future<void> done(String id);

  /// Puts text on the computer's clipboard.
  Future<void> copy(String text);

  /// The picture on the computer's clipboard, if it holds one.
  Future<ClipboardPicture?> pastePicture();

  /// Puts a picture on the computer's clipboard.
  Future<void> copyPicture(ClipboardPicture picture);

  /// Tells the computer the phone's battery level.
  Future<void> status(String phone, {required int battery, required bool charging});

  /// Shows one of the phone's notifications on the computer.
  Future<void> notice(String phone, PhoneNotification notification);

  /// A call on the phone began or ended.
  Future<void> call(String phone, {required bool active});

  /// The phone's answer to an approval: a signature, or "no".
  Future<void> approved(String id, String answer);

  /// Silences the computer's notifications, or stops silencing them.
  Future<void> dnd({required bool on});

  /// Uploads files that waited on the phone into the computer's inbox and
  /// has it say what arrived. The answer is the ones that got there.
  Future<List<WaitingFile>> send(List<WaitingFile> files, {required String phone});
}

class SshShareChannel implements ShareChannel {
  SshShareChannel(this.session);

  final LiveSession session;

  @override
  Future<(Stream<ShareEvent>, void Function())> link(String phone) async {
    final link = await session.ssh.shareLink(phone: phone);
    return (link.events(), link.stop);
  }

  @override
  Future<String> fetch(ShareEvent_File file) async {
    final files = await session.ssh.openFiles();
    final found = await files.stat(path: file.path);
    // Under the name it was sent as (an archive's file has a longer one).
    final entry = RemoteEntry(
      name: file.name,
      path: found.path,
      kind: found.kind,
      isDir: found.isDir,
      size: found.size,
      permissions: found.permissions,
      modified: found.modified,
    );
    final queue = TransferQueue.of(session);
    final job = queue.add(DownloadTask(files: files, entry: entry));
    final finished = Completer<String>();
    void check() {
      if (finished.isCompleted) return;
      switch (job.state) {
        case TransferState.done:
          finished.complete(job.result ?? file.name);
        case TransferState.failed || TransferState.cancelled:
          finished.completeError(job.error ?? 'The download stopped.');
        case TransferState.waiting || TransferState.running:
          break;
      }
    }

    queue.addListener(check);
    check();
    try {
      return await finished.future;
    } finally {
      queue.removeListener(check);
    }
  }

  @override
  Future<void> done(String id) => session.ssh.shareDone(id: id);

  @override
  Future<void> copy(String text) => session.ssh.shareCopy(text: text);

  @override
  Future<ClipboardPicture?> pastePicture() async {
    final picture = await session.ssh.sharePastePicture();
    return picture == null ? null : ClipboardPicture(picture.kind, picture.bytes);
  }

  @override
  Future<void> copyPicture(ClipboardPicture picture) => session.ssh.shareCopyPicture(kind: picture.kind, picture: picture.bytes);

  @override
  Future<void> status(String phone, {required int battery, required bool charging}) =>
      session.ssh.phoneStatus(phone: phone, battery: battery, charging: charging);

  @override
  Future<void> notice(String phone, PhoneNotification notification) =>
      session.ssh.phoneNotice(phone: phone, app: notification.app, title: notification.title, text: notification.text);

  @override
  Future<void> call(String phone, {required bool active}) => session.ssh.phoneCall(phone: phone, active: active);

  @override
  Future<void> approved(String id, String answer) => session.ssh.shareApproved(id: id, answer: answer);

  @override
  Future<void> dnd({required bool on}) => session.ssh.deskDo(action: DeskAction.dnd(enabled: on));

  @override
  Future<List<WaitingFile>> send(List<WaitingFile> files, {required String phone}) async {
    final remote = await session.ssh.openFiles();
    final inbox = await session.ssh.shareInbox();
    final queue = TransferQueue.of(session);
    final jobs = {
      for (final f in files)
        f: queue.add(
          UploadTask(
            files: remote,
            source: UploadSource(name: f.name, path: f.path),
            remoteFolder: inbox,
          ),
        ),
    };
    final finished = Completer<void>();
    void check() {
      if (!finished.isCompleted && jobs.values.every((j) => !j.isActive)) finished.complete();
    }

    queue.addListener(check);
    check();
    await finished.future;
    queue.removeListener(check);
    final arrived = [
      for (final e in jobs.entries)
        if (e.value.state == TransferState.done) e.key,
    ];
    if (arrived.isNotEmpty) await session.ssh.shareReceived(phone: phone, names: [for (final f in arrived) f.name]);
    return arrived;
  }
}

/// A newer version of this app that a computer sent.
class NewerApp {
  const NewerApp({required this.path, required this.from});

  final String path;

  /// The computer's name.
  final String from;
}

/// A file a computer sent to the phone.
class ReceivedFile {
  const ReceivedFile({required this.name, required this.path, required this.from, required this.at});

  final String name;

  /// Where it is on the phone.
  final String path;

  /// The computer's name.
  final String from;
  final DateTime at;
}

/// Keeps each connected, paired computer linked with the phone: files it
/// has waiting (`multiplex send`, also from while the phone was away) are
/// fetched, and the two clipboards follow each other.
///
/// The link lives as long as the connection does, which the app keeps in
/// the background while sessions are open.
class ComputerLinks extends ChangeNotifier with WidgetsBindingObserver {
  ComputerLinks(
    this._sessions,
    this._store, {
    ShareChannel Function(LiveSession session)? channel,
    Future<void> Function(String title, String body)? notify,
    AgentNotices? agentNotices,
    PhoneHands hands = const AndroidPhoneHands(),
    HerdLink Function(LiveSession session)? herd,
    Duration answerWithin = const Duration(seconds: 15),
    Future<String?> Function()? readClipboard,
    Future<void> Function(String text)? writeClipboard,
    Future<ClipboardPicture?> Function()? readPicture,
    Future<void> Function(ClipboardPicture picture)? writePicture,
    String Function(Uint8List picture)? markOf,
    PhoneOutbox? outbox,
    PhoneBridge phone = const PhoneBridge(),
    Future<bool> Function(String reason)? confirm,
    String Function(String privateKey, String id, String reason, String challenge)? sign,
    String? Function(String privateKey, String data)? describeSigning,
    String Function(String privateKey, String data)? signRequest,
    bool Function()? appInFront,
    UpdatePlatform updates = const AndroidUpdatePlatform(),
    Future<void> Function(Host host)? connect,
    Duration retryAfter = const Duration(seconds: 45),
  }) : outbox = outbox ?? PhoneOutbox(),
       // ignore: prefer_initializing_formals
       _connect = connect,
       // ignore: prefer_initializing_formals
       _retryAfter = retryAfter,
       // ignore: prefer_initializing_formals
       _updates = updates,
       _confirm = confirm ?? const DeviceUnlock().confirmTo,
       _sign = sign ?? ((key, id, reason, challenge) => approvalSign(privateKey: key, id: id, reason: reason, challenge: challenge)),
       _describeSigning = describeSigning ?? ((key, data) => signingDescribe(privateKey: key, data: data)),
       _signRequest = signRequest ?? ((key, data) => signingSign(privateKey: key, data: data)),
       _appInFront = appInFront ?? (() => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed),
       // ignore: prefer_initializing_formals
       _phone = phone,
       _channel = channel ?? SshShareChannel.new,
       _notify = notify ?? _postOnPhone,
       _agentNotices = agentNotices ?? PhoneAgentNotices(),
       // ignore: prefer_initializing_formals
       _hands = hands,
       _herd = herd ?? ((session) => SshHerdLink(() => session.ssh)),
       // ignore: prefer_initializing_formals
       _answerWithin = answerWithin,
       _readClipboard = readClipboard ?? _phoneClipboard,
       _writeClipboard = writeClipboard ?? _setPhoneClipboard,
       _readPicture = readPicture ?? PhoneClipboardPictures.read,
       _writePicture = writePicture ?? PhoneClipboardPictures.write,
       _markOf = markOf ?? ((picture) => sharePictureMark(picture: picture)) {
    _sessions.addListener(_sync);
    _store.addListener(_keepConnected);
    WidgetsBinding.instance.addObserver(this);
    _agentNotices.listen(_answerAgent);
    // A moment after start (Tailscale is still coming up), then now and
    // again: a computer that was out of reach may be back.
    _firstTry = Timer(const Duration(seconds: 2), _keepConnected);
    _retry = Timer.periodic(const Duration(seconds: 60), (_) => _keepConnected());
    _phoneNotices = _phone.notifications().listen(_mirror);
    _phoneChanges = _phone.changes().listen((change) {
      for (final link in _links.values) {
        if (change.call != null) link.call(change.call!);
        if (change.dnd != null) link.dnd(change.dnd!);
      }
    });
    _sync();
  }

  final PhoneBridge _phone;

  // Staying connected.

  /// Connects without asking anything. Replaced in tests.
  final Future<void> Function(Host host)? _connect;
  final Duration _retryAfter;
  Timer? _firstTry;
  Timer? _retry;

  /// When each computer was last tried, so one that is out of reach is
  /// not tried over and over.
  final Map<String, DateTime> _tried = {};
  final Set<String> _connecting = {};

  /// How often in a row each computer was out of reach, and the next try
  /// that is already set for it.
  final Map<String, int> _failed = {};
  final Map<String, Timer> _again = {};

  /// How long to leave a computer alone before trying it again, after it
  /// was out of reach [failures] times in a row: soon at first, then less
  /// and less often, never longer than [longest]. Right after the app
  /// starts the first try often fails only because Tailscale needs a few
  /// more seconds (seen on mobile data: the link came a minute late when
  /// every retry waited the full time). With no failure the full time
  /// applies: a connection that has just ended is not dialled at once.
  static Duration waitAfter(int failures, Duration longest) {
    if (failures <= 0) return longest;
    final soon = Duration(seconds: 3 * (1 << (failures - 1).clamp(0, 10)));
    return soon < longest ? soon : longest;
  }

  /// Computers whose connection was closed on purpose: left alone until
  /// the app is next brought to the front.
  final Set<String> _leftAlone = {};

  /// The computers that had a session at the last look.
  Set<String> _hadSession = {};

  /// Links every paired computer that wants it and has no connection.
  /// Never asks anything: a computer that would need a question (an
  /// unknown host key, a fingerprint first) is simply not connected here.
  void _keepConnected() {
    final now = DateTime.now();
    for (final host in _store.hosts) {
      if (!host.computer || !host.stayConnected || host.askUnlock) continue;
      if (_leftAlone.contains(host.id) || _connecting.contains(host.id)) continue;
      if (_sessions.sessions.any((s) => s.host.id == host.id)) continue;
      final last = _tried[host.id];
      if (last != null && now.difference(last) < waitAfter(_failed[host.id] ?? 0, _retryAfter)) continue;
      _tried[host.id] = now;
      _connecting.add(host.id);
      final connect = _connect ?? (Host h) => _sessions.connect(h, const SilentPrompter()).then((_) {});
      unawaited(
        connect(host)
            .then((_) {
              _failed.remove(host.id);
            })
            .catchError((Object _) {
              // Out of reach for now: tried again by itself, soon at
              // first and then less often.
              final failures = (_failed[host.id] ?? 0) + 1;
              _failed[host.id] = failures;
              _again[host.id]?.cancel();
              _again[host.id] = Timer(waitAfter(failures, _retryAfter) + const Duration(milliseconds: 10), _keepConnected);
            })
            .whenComplete(() => _connecting.remove(host.id)),
      );
    }
  }

  /// Asks the owner to confirm with a fingerprint, face or PIN.
  final Future<bool> Function(String reason) _confirm;

  /// Signs an approval with the phone's key (in the Rust core).
  final String Function(String privateKey, String id, String reason, String challenge) _sign;
  final bool Function() _appInFront;

  /// What a request from the computer's SSH agent is for (read from the
  /// request itself, in the Rust core); null when it is not something an
  /// SSH key signs.
  final String? Function(String privateKey, String data) _describeSigning;

  /// Signs such a request with the phone's key.
  final String Function(String privateKey, String data) _signRequest;

  /// Completed when the app next comes to the front (a fingerprint
  /// prompt can only show then).
  Completer<void>? _front;

  /// Waits until the app is in front, for at most [limit]. False if it
  /// did not get there.
  Future<bool> _whenInFront(Duration limit) async {
    if (_appInFront()) return true;
    final front = _front ??= Completer<void>();
    return front.future.then((_) => true).timeout(limit, onTimeout: () => false);
  }

  StreamSubscription<PhoneNotification>? _phoneNotices;
  StreamSubscription<({bool? call, bool? dnd})>? _phoneChanges;

  /// Apps that have posted a notification since the app started, for the
  /// list where each can be kept off the computer.
  final Set<String> seenApps = {};

  /// A phone notification goes to every linked computer that wants it.
  void _mirror(PhoneNotification notification) {
    if (notification.app.isNotEmpty && seenApps.add(notification.app)) notifyListeners();
    for (final link in _links.values) {
      link.mirror(notification);
    }
  }

  final SessionManager _sessions;
  final VaultStore _store;
  final ShareChannel Function(LiveSession session) _channel;
  final Future<void> Function(String title, String body) _notify;
  final AgentNotices _agentNotices;
  final PhoneHands _hands;
  final HerdLink Function(LiveSession session) _herd;
  final Duration _answerWithin;
  final Future<String?> Function() _readClipboard;
  final Future<void> Function(String text) _writeClipboard;
  final Future<ClipboardPicture?> Function() _readPicture;
  final Future<void> Function(ClipboardPicture picture) _writePicture;

  /// A short name for exactly one picture (the same on the computer).
  final String Function(Uint8List picture) _markOf;
  final Map<LiveSession, _Link> _links = {};

  /// Files shared to a computer that could not be reached at the time.
  final PhoneOutbox outbox;

  /// The app's own, set once at start (null in tests that do not need it).
  static ComputerLinks? app;

  /// Files received since the app started, newest first.
  final List<ReceivedFile> received = [];

  /// Checks and installs an app file (the phone's own updater).
  final UpdatePlatform _updates;

  /// A newer Multiplex that a computer sent, checked and ready to install.
  NewerApp? newerApp;

  /// A received file that is an Android app: if it is a newer Multiplex,
  /// signed with the same key as this one, it is offered for installing.
  /// Anything else stays an ordinary received file.
  Future<void> _maybeNewerApp(ReceivedFile file) async {
    if (!file.name.toLowerCase().endsWith('.apk')) return;
    try {
      // The updater only installs from its own folder.
      final folder = await _updates.downloadDir();
      final copy = await File(file.path).copy('${folder.path}${Platform.pathSeparator}from-computer.apk');
      if (!(await _updates.checkApk(copy.path)).ok) {
        await copy.delete();
        return;
      }
      newerApp = NewerApp(path: copy.path, from: file.from);
      notifyListeners();
      await _notify('A newer Multiplex from ${file.from}', 'Open that computer\'s Sharing page in Multiplex to install it');
    } catch (_) {
      // Not installable from here: it is still in the downloads.
    }
  }

  /// Hands the newer app to Android's installer. False when Android has
  /// not yet let Multiplex install apps: its settings page is then opened.
  Future<bool> installNewerApp() async {
    final app = newerApp;
    if (app == null) return false;
    if (!await _updates.canInstall()) {
      await _updates.openInstallPermission();
      return false;
    }
    await _updates.install(app.path);
    return true;
  }

  /// An agent on [host] began to wait, or finished: a notification that
  /// can be answered where it is. Its choices become buttons; without
  /// choices an answer can be typed into it. A tap opens the agent.
  ///
  /// With the app lock on there are no buttons and nothing to type into:
  /// an answer then waits for the app to be opened and unlocked.
  Future<void> _tellOfAgent(
    Host host, {
    required String name,
    required String title,
    required String workspace,
    required bool waiting,
    required String session,
    required String pane,
    required HerdAsked? asked,
  }) async {
    final where = [if (title.isNotEmpty) title, if (workspace.isNotEmpty) workspace, host.title].join(' · ');
    final heading = waiting ? '$name needs you' : '$name is done';
    // The computer did not say where it is: told as it always was.
    if (session.isEmpty || pane.isEmpty) return _notify(heading, where);
    final question = asked?.question.trim() ?? '';
    final answerable = !_store.settings.appLock;
    await _agentNotices.post(
      AgentNotice(
        place: AgentPlace(hostId: host.id, session: session, pane: pane, mark: asked?.mark ?? ''),
        title: heading,
        waiting: waiting,
        summary: question.isEmpty ? where : question.split('\n').where((line) => line.trim().isNotEmpty).join(' · '),
        body: question.isEmpty ? where : '$question\n\n$where',
        choices: [
          if (answerable && asked != null)
            for (final choice in asked.choices) (key: choice.key, label: choice.label),
        ],
        reply: answerable && asked == null,
      ),
    );
  }

  /// An answer given in a notification. Null when it was sent; otherwise
  /// the words that say why not. The computer sends it on only while the
  /// agent still asks what the answer was given to.
  Future<String?> _answerAgent(AgentAnswer answer) async {
    final place = answer.place;
    final host = _store.host(place.hostId);
    if (host == null || !host.computer) return 'That computer is no longer paired with this phone.';
    if (_store.settings.appLock) return 'Open Multiplex to answer.';
    final (choice, text) = (answer.choice, answer.text?.trim() ?? '');
    if (choice == null && text.isEmpty) return 'There was nothing to send.';
    // The app may have just been started for this: the link comes up first.
    _keepConnected();
    final until = DateTime.now().add(_answerWithin);
    LiveSession? connected() => _sessions.sessions.where((s) => s.host.id == host.id && s.connected).firstOrNull;
    var session = connected();
    while (session == null && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      session = connected();
    }
    if (session == null) return '${host.title} is not connected. Open Multiplex to answer.';
    try {
      final herd = _herd(session);
      if (choice != null) {
        await herd.answerChoice(place.session, place.pane, place.mark, choice);
      } else {
        await herd.answerText(place.session, place.pane, place.mark, text);
      }
      return null;
    } catch (e) {
      return errorSentence(e, fallback: '${host.title} did not answer. Nothing was sent.');
    }
  }

  static const _notices = MethodChannel('multiplex/sessions');

  static Future<void> _postOnPhone(String title, String body) async {
    try {
      await _notices.invokeMethod<void>('notifyDone', {'title': title, 'body': body});
    } on MissingPluginException {
      // No notifications on this platform.
    } on PlatformException {
      // A notification is never worth an error.
    }
  }

  static Future<String?> _phoneClipboard() async {
    try {
      // With a time limit: while the app has no screen (swiped away, or
      // started with the phone) Flutter's clipboard call is never
      // answered, and a link must not wait on it.
      return (await Clipboard.getData(Clipboard.kTextPlain).timeout(const Duration(seconds: 1)))?.text;
    } on TimeoutException {
      return null;
    } on PlatformException {
      // Android only lets the app in front read the clipboard.
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> _setPhoneClipboard(String text) async {
    // Android's own way first: it works with or without a screen.
    if (await PhoneClipboardPictures.writeText(text)) return;
    try {
      await Clipboard.setData(ClipboardData(text: text)).timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // No screen to answer.
    } on MissingPluginException {
      // No clipboard on this platform.
    } on PlatformException {
      // A clipboard is never worth an error.
    }
  }

  void _arrived(ReceivedFile file) {
    received.insert(0, file);
    notifyListeners();
    unawaited(_maybeNewerApp(file));
  }

  /// The saved computer behind a session (its settings may have changed
  /// since it connected).
  Host _host(LiveSession session) => _store.host(session.host.id) ?? session.host;

  /// Starts a link for each connected computer, restarts it after a
  /// reconnect, and ends those whose connection is gone.
  void _sync() {
    // A session that is gone from the list was closed on purpose (a lost
    // connection stays listed while it is being restored).
    final have = {for (final s in _sessions.sessions) s.host.id};
    _leftAlone.addAll(_hadSession.difference(have));
    _hadSession = have;
    final live = {
      for (final s in _sessions.sessions)
        if (s.host.computer && s.connected) s,
    };
    for (final session in _links.keys.toList()) {
      if (!live.contains(session) || !identical(_links[session]!.ssh, session.ssh)) _links.remove(session)!.close();
    }
    for (final session in live) {
      _links.putIfAbsent(session, () => _Link(this, session)..start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in front: what was copied on the phone meanwhile goes over.
    if (state == AppLifecycleState.resumed) {
      _front?.complete();
      _front = null;
      // The owner is back: what they closed may connect again.
      _leftAlone.clear();
      _keepConnected();
      for (final link in _links.values) {
        link.sendPhoneClipboard();
      }
    }
  }

  /// Sends the phone's clipboard to a computer now, whatever the setting.
  /// False when it holds neither text nor a picture, or the computer is
  /// not linked.
  Future<bool> sendClipboardTo(LiveSession session) async => await _links[session]?.sendPhoneClipboard(force: true) ?? false;

  @override
  void dispose() {
    _sessions.removeListener(_sync);
    _store.removeListener(_keepConnected);
    _firstTry?.cancel();
    _retry?.cancel();
    for (final timer in _again.values) {
      timer.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    _agentNotices.stop();
    _phoneNotices?.cancel();
    _phoneChanges?.cancel();
    for (final link in _links.values) {
      link.close();
    }
    _links.clear();
    super.dispose();
  }
}

class _Link {
  _Link(this.owner, this.session) : ssh = session.ssh, channel = owner._channel(session);

  final ComputerLinks owner;
  final LiveSession session;

  /// The connection this link runs on (a reconnect brings a new one).
  final Object ssh;
  final ShareChannel channel;
  StreamSubscription<ShareEvent>? _events;
  void Function()? _stop;
  Timer? _status;
  bool _closed = false;

  /// The text both clipboards last agreed on, so nothing bounces back.
  String? _lastClip;

  /// The mark of the last picture that went either way.
  String? _lastPicture;

  /// Whether [_lastClip] is really what the phone's clipboard held. Android
  /// only lets the app in front read it, so a link that starts while the
  /// app is not on screen does not know yet; until it does, nothing on
  /// the phone counts as new.
  bool _clipKnown = false;

  /// Files being fetched, so one is not fetched twice.
  final Set<String> _fetching = {};

  Host get host => owner._host(session);

  Future<void> start() async {
    // What is on the phone's clipboard now is not news for the computer.
    final now = await owner._readClipboard();
    if (now != null) {
      _lastClip = now;
      _clipKnown = true;
    } else {
      final picture = await owner._readPicture();
      if (picture != null) {
        _lastPicture = owner._markOf(picture.bytes);
        _clipKnown = true;
      }
    }
    try {
      final (events, stop) = await channel.link(_name);
      if (_closed) {
        stop();
        return;
      }
      _stop = stop;
      _events = events.listen(_on);
      unawaited(_sendWaiting());
      unawaited(_reportStatus());
      // Also the phone's sign of life: without one for a while the
      // computer takes the phone for gone.
      _status = Timer.periodic(const Duration(seconds: 30), (_) => _reportStatus());
    } catch (_) {
      // An older package without sharing, or the connection just dropped:
      // everything else about the computer still works.
    }
  }

  void _on(ShareEvent event) {
    switch (event) {
      case ShareEvent_File():
        unawaited(_fetch(event));
      case ShareEvent_Clip(:final text):
        if (!host.shareClipboard || text == _lastClip) return;
        _lastClip = text;
        // Whatever picture crossed before is no longer what the clipboards hold.
        _lastPicture = null;
        _clipKnown = true;
        // Sizes only: what is on a clipboard is nobody's business.
        if (kDebugMode) debugPrint('mpxlink clipboard to the phone (${text.length} characters)');
        unawaited(owner._writeClipboard(text));
      case ShareEvent_Picture(:final size, :final mark):
        if (!host.shareClipboard || mark == _lastPicture) return;
        _lastPicture = mark;
        _lastClip = null;
        _clipKnown = true;
        if (kDebugMode) debugPrint('mpxlink clipboard picture to the phone ($size bytes)');
        unawaited(_fetchPicture());
      case ShareEvent_Ring(:final seconds):
        unawaited(owner._phone.ring(seconds));
      case ShareEvent_Sms(:final to, :final text):
        unawaited(_sendSms(to, text));
      case ShareEvent_Approve(:final id, :final reason, :final challenge):
        unawaited(_approve(id, reason, challenge));
      case ShareEvent_Sign(:final id, :final data):
        unawaited(_signFor(id, data));
      case ShareEvent_Hands(:final id, :final keys, :final pointer, :final look):
        unawaited(_hands(id, keys, pointer, look));
      case ShareEvent_Agent(:final name, :final title, :final workspace, :final waiting, :final session, :final pane, :final asked):
        // A coding agent on the computer wants an answer, or is done.
        unawaited(owner._tellOfAgent(host, name: name, title: title, workspace: workspace, waiting: waiting, session: session, pane: pane, asked: asked));
      case ShareEvent_Settled(:final session, :final pane):
        // It was answered at the computer, went on, or closed.
        unawaited(owner._agentNotices.withdraw(AgentPlace(hostId: host.id, session: session, pane: pane).tag));
    }
  }

  /// The name this phone is paired under ('' when that was not kept: the
  /// computer then takes the only paired phone).
  String get _name => host.pairedAs ?? '';

  /// Tells the computer the battery level, now and every half minute.
  Future<void> _reportStatus() async {
    final battery = await owner._phone.battery();
    if (battery == null || _closed) return;
    try {
      await channel.status(_name, battery: battery.level, charging: battery.charging);
    } catch (_) {
      // An older package: the rest still works.
    }
  }

  /// The computer asks for a yes. Only a fingerprint (or face, or PIN)
  /// on this phone gives one: the answer is then signed with the phone's
  /// key. Anything else, including not answering in time, is a no.
  Future<void> _approve(String id, String reason, String challenge) async {
    var answer = 'no';
    try {
      // The prompt needs the app on screen; a notification asks for that.
      if (!owner._appInFront()) await owner._notify('${host.title} asks for your approval', 'Open Multiplex to answer: $reason');
      final key = owner._store.key(host.keyId);
      if (key != null && !key.encrypted && await owner._whenInFront(const Duration(seconds: 50)) && await owner._confirm('Approve on ${host.title}: $reason')) {
        answer = owner._sign(key.privatePem, id, reason, challenge);
      }
    } catch (_) {
      // A cancelled or failed check is a no.
    }
    if (_closed) return;
    unawaited(channel.approved(id, answer).catchError((Object _) {}));
  }

  /// The computer's SSH agent wants this phone's key used: a login
  /// somewhere, or a signature (a Git commit). The phone reads the request
  /// itself to say what it is, and signs only after a fingerprint. What it
  /// cannot read as one of those is refused without asking.
  Future<void> _signFor(String id, String data) async {
    var answer = 'no';
    try {
      final key = owner._store.key(host.keyId);
      final what = key == null || key.encrypted ? null : owner._describeSigning(key.privatePem, data);
      if (key != null && what != null) {
        if (!owner._appInFront()) await owner._notify('${host.title} wants to use this phone\'s key', 'Open Multiplex to answer: $what');
        if (await owner._whenInFront(const Duration(seconds: 50)) && await owner._confirm('$what (asked by ${host.title})')) {
          answer = owner._signRequest(key.privatePem, data);
        }
      }
    } catch (_) {
      // A cancelled or failed check is a no.
    }
    if (_closed) return;
    unawaited(channel.approved(id, answer).catchError((Object _) {}));
  }

  /// The computer asked for a text message to be sent. It hears what
  /// became of it, whatever that is.
  /// The computer wants this phone to type and click on the device it is
  /// connected to, or to look at it. Only for a computer the owner has
  /// switched this on for; every ask is answered, so the computer knows
  /// whether it was done.
  Future<void> _hands(String id, Uint8List keys, Uint8List pointer, bool look) async {
    String answer;
    if (!host.allowHands) {
      answer = 'no: Typing through this phone is switched off for ${host.title}. It is under Sharing and notifications on the phone.';
    } else if (look) {
      final seen = await owner._hands.look();
      answer = seen.path ?? 'no: ${seen.problem ?? 'No picture could be taken.'}';
    } else {
      final problem = await owner._hands.send(keys, pointer);
      answer = problem == null ? 'ok' : 'no: $problem';
    }
    if (_closed) return;
    unawaited(channel.approved(id, answer).catchError((Object _) {}));
  }

  Future<void> _sendSms(String to, String text) async {
    final problem = host.allowSms ? await owner._phone.sendSms(to, text) : 'Sending text messages from this computer is switched off on the phone.';
    if (_closed) return;
    final reply = PhoneNotification(app: 'Messages', title: problem == null ? 'Sent to $to' : 'Not sent to $to', text: problem ?? text);
    unawaited(channel.notice(_name, reply).catchError((Object _) {}));
  }

  /// A call began or ended: the computer pauses, then carries on.
  void call(bool active) {
    if (_closed || !host.pauseMediaOnCalls) return;
    unawaited(channel.call(_name, active: active).catchError((Object _) {}));
  }

  /// The phone's Do Not Disturb went on or off.
  void dnd(bool on) {
    if (_closed || !host.syncDnd) return;
    unawaited(channel.dnd(on: on).catchError((Object _) {}));
  }

  void mirror(PhoneNotification notification) {
    final host = this.host;
    if (_closed || !host.mirrorNotifications || host.mutedApps.contains(notification.app)) return;
    unawaited(channel.notice(_name, notification).catchError((Object _) {}));
  }

  Future<void> _fetch(ShareEvent_File file) async {
    if (!_fetching.add(file.id)) return;
    try {
      final path = await channel.fetch(file);
      await channel.done(file.id);
      if (_closed) return;
      owner._arrived(ReceivedFile(name: file.name, path: path, from: host.title, at: DateTime.now()));
      await owner._notify('${file.name} from ${host.title}', 'Saved in Multiplex downloads');
    } catch (_) {
      // It stays in the computer's outbox and is offered again next time.
    } finally {
      _fetching.remove(file.id);
    }
  }

  /// What was shared while the computer was out of reach goes now.
  Future<void> _sendWaiting() async {
    try {
      final waiting = await owner.outbox.waiting(host.id);
      if (waiting.isEmpty || _closed) return;
      for (final sent in await channel.send(waiting, phone: host.pairedAs ?? 'your phone')) {
        await owner.outbox.remove(sent);
      }
    } catch (_) {
      // They keep waiting for the next connection.
    }
  }

  /// The picture the computer said is on its clipboard, onto the phone's.
  Future<void> _fetchPicture() async {
    try {
      final picture = await channel.pastePicture();
      // Meanwhile replaced on the computer by something else: let it go.
      if (picture == null || _closed || owner._markOf(picture.bytes) != _lastPicture) return;
      await owner._writePicture(picture);
    } catch (_) {
      // The next one copied there is a new chance.
    }
  }

  /// Sends the picture on the phone's clipboard if it is a new one.
  Future<bool> _sendPhonePicture({required bool force}) async {
    final picture = await owner._readPicture();
    if (picture == null) return false;
    final mark = owner._markOf(picture.bytes);
    // As with text: the first look only notes what is there.
    if (!force && !_clipKnown) {
      _lastPicture = mark;
      _clipKnown = true;
      return false;
    }
    if (!force && mark == _lastPicture) return false;
    _lastPicture = mark;
    _lastClip = null;
    _clipKnown = true;
    try {
      await channel.copyPicture(picture);
      if (kDebugMode) debugPrint('mpxlink clipboard picture to the computer (${picture.bytes.length} bytes)');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends the phone's clipboard if it changed. True when it was sent.
  Future<bool> sendPhoneClipboard({bool force = false}) async {
    if (_closed || (!force && !host.shareClipboard)) return false;
    final text = await owner._readClipboard();
    // No text: it may hold a picture.
    if (text == null || text.isEmpty) return _sendPhonePicture(force: force);
    // The first look only notes what is there: it was copied before this
    // link could see the clipboard, so it is not news, and it must not
    // replace what the computer holds.
    if (!force && !_clipKnown) {
      _lastClip = text;
      _clipKnown = true;
      return false;
    }
    if (text.isEmpty || (!force && text == _lastClip)) return false;
    _lastClip = text;
    _lastPicture = null;
    _clipKnown = true;
    try {
      await channel.copy(text);
      if (kDebugMode) debugPrint('mpxlink clipboard to the computer (${text.length} characters)');
      return true;
    } catch (_) {
      return false;
    }
  }

  void close() {
    _closed = true;
    _status?.cancel();
    _events?.cancel();
    _stop?.call();
  }
}
