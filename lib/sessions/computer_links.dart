import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app/lock_gate.dart';
import '../data/models.dart';
import '../data/vault_store.dart';
import '../platform/phone_bridge.dart';
import '../src/rust/api/desk_types.dart';
import '../src/rust/api/sftp_types.dart';
import '../src/rust/api/share.dart';
import '../ui/files/transfer_queue.dart';
import '../ui/files/transfer_tasks.dart';
import '../update/update_platform.dart';
import 'phone_outbox.dart';
import 'session_manager.dart';

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
    Future<String?> Function()? readClipboard,
    Future<void> Function(String text)? writeClipboard,
    PhoneOutbox? outbox,
    PhoneBridge phone = const PhoneBridge(),
    Future<bool> Function(String reason)? confirm,
    String Function(String privateKey, String id, String reason, String challenge)? sign,
    String? Function(String privateKey, String data)? describeSigning,
    String Function(String privateKey, String data)? signRequest,
    bool Function()? appInFront,
    UpdatePlatform updates = const AndroidUpdatePlatform(),
  }) : outbox = outbox ?? PhoneOutbox(),
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
       _readClipboard = readClipboard ?? _phoneClipboard,
       _writeClipboard = writeClipboard ?? ((text) => Clipboard.setData(ClipboardData(text: text))) {
    _sessions.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
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
  final Future<String?> Function() _readClipboard;
  final Future<void> Function(String text) _writeClipboard;
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
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      // Android only lets the app in front read the clipboard.
      return null;
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
      for (final link in _links.values) {
        link.sendPhoneClipboard();
      }
    }
  }

  /// Sends the phone's clipboard to a computer now, whatever the setting.
  /// False when it holds no text or the computer is not linked.
  Future<bool> sendClipboardTo(LiveSession session) async => await _links[session]?.sendPhoneClipboard(force: true) ?? false;

  @override
  void dispose() {
    _sessions.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
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

  /// Files being fetched, so one is not fetched twice.
  final Set<String> _fetching = {};

  Host get host => owner._host(session);

  Future<void> start() async {
    // What is on the phone's clipboard now is not news for the computer.
    _lastClip = await owner._readClipboard();
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
      _status = Timer.periodic(const Duration(minutes: 5), (_) => _reportStatus());
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
        // Sizes only: what is on a clipboard is nobody's business.
        if (kDebugMode) debugPrint('mpxlink clipboard to the phone (${text.length} characters)');
        unawaited(owner._writeClipboard(text));
      case ShareEvent_Ring(:final seconds):
        unawaited(owner._phone.ring(seconds));
      case ShareEvent_Sms(:final to, :final text):
        unawaited(_sendSms(to, text));
      case ShareEvent_Approve(:final id, :final reason, :final challenge):
        unawaited(_approve(id, reason, challenge));
      case ShareEvent_Sign(:final id, :final data):
        unawaited(_signFor(id, data));
      case ShareEvent_Agent(:final name, :final title, :final workspace, :final waiting):
        // A coding agent on the computer wants an answer, or is done.
        final where = [if (title.isNotEmpty) title, if (workspace.isNotEmpty) workspace, host.title].join(' · ');
        unawaited(owner._notify(waiting ? '$name needs you' : '$name is done', where));
    }
  }

  /// The name this phone is paired under ('' when that was not kept: the
  /// computer then takes the only paired phone).
  String get _name => host.pairedAs ?? '';

  /// Tells the computer the battery level, now and every few minutes.
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

  /// Sends the phone's clipboard if it changed. True when it was sent.
  Future<bool> sendPhoneClipboard({bool force = false}) async {
    if (_closed || (!force && !host.shareClipboard)) return false;
    final text = await owner._readClipboard();
    if (text == null || text.isEmpty || (!force && text == _lastClip)) return false;
    _lastClip = text;
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
