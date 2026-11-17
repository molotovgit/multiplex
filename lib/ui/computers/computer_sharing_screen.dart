import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../platform/phone_bridge.dart';
import '../../sessions/computer_links.dart';
import '../common/widgets.dart';
import '../settings/settings_widgets.dart';

/// What a paired computer and this phone share by themselves while they
/// are connected: the clipboard, and the phone's notifications.
class ComputerSharingScreen extends StatefulWidget {
  const ComputerSharingScreen({super.key, required this.hostId, this.phone = const PhoneBridge(), this.links});

  final String hostId;

  /// Replaced in tests.
  final PhoneBridge phone;
  final ComputerLinks? links;

  static Future<void> open(BuildContext context, String hostId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComputerSharingScreen(hostId: hostId)));

  @override
  State<ComputerSharingScreen> createState() => _ComputerSharingScreenState();
}

class _ComputerSharingScreenState extends State<ComputerSharingScreen> with WidgetsBindingObserver {
  /// Null until Android has answered.
  bool? _access;

  ComputerLinks? get _links => widget.links ?? ComputerLinks.app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The switch for text messages was turned on and Android is asking.
  bool _askingSms = false;

  /// Back from Android's settings or its question: the answer may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkAccess();
    if (_askingSms) _smsAnswered();
  }

  Future<void> _smsAnswered() async {
    _askingSms = false;
    final allowed = await widget.phone.smsPermission();
    if (!mounted) return;
    final store = AppScope.store(context);
    final host = store.host(widget.hostId);
    if (host == null) return;
    if (allowed) {
      store.saveHost(host.copyWith(allowSms: true));
    } else {
      Toast.show(context, 'Android did not allow Multiplex to send text messages');
    }
  }

  Future<void> _setSms(bool on) async {
    final store = AppScope.store(context);
    final host = store.host(widget.hostId);
    if (host == null) return;
    if (!on || await widget.phone.smsPermission()) {
      store.saveHost(host.copyWith(allowSms: on));
      return;
    }
    // Android asks; the answer is read when the app is in front again.
    _askingSms = true;
    await widget.phone.requestSmsPermission();
  }

  Future<void> _checkAccess() async {
    final access = await widget.phone.notificationAccess();
    if (mounted) setState(() => _access = access);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    final host = store.host(widget.hostId);
    if (host == null) return const Scaffold(body: SizedBox.shrink());
    final colors = AppColorsTheme.of(context);
    final links = _links;
    return Scaffold(
      appBar: AppBar(title: const Text('Sharing')),
      body: ContentWidth(
        child: ListenableBuilder(
          listenable: links ?? const _Never(),
          builder: (context, _) {
            // Apps seen since the app started, and the ones kept off before.
            final apps = {...?links?.seenApps, ...host.mutedApps}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            return ListView(
              children: [
                // The computer sent a newer Multiplex (checked: same app, same signing key).
                if (links?.newerApp case final app? when app.from == host.title)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 12, SettingsLayout.gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        NoticeBox(
                          tone: NoticeTone.success,
                          text: '${host.title} sent a newer version of Multiplex. It is the same app, signed with the same key.',
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final started = await links!.installNewerApp();
                              if (!started && context.mounted) Toast.show(context, 'Allow Multiplex to install apps, then tap Install again');
                            },
                            icon: const Icon(Icons.system_update_alt),
                            label: const Text('Install'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SectionHeader('Connection'),
                SwitchListTile(
                  title: const Text('Stay connected'),
                  subtitle: Text(
                    'Links this phone to ${host.title} whenever Multiplex runs, also in the background, so files, the clipboard and '
                    'finding the phone work without opening anything. Uses some battery',
                  ),
                  value: host.stayConnected,
                  onChanged: (on) => store.saveHost(host.copyWith(stayConnected: on)),
                ),
                const SectionHeader('Clipboard'),
                SwitchListTile(
                  title: const Text('Share the clipboard'),
                  subtitle: Text('Text copied on ${host.title} lands on this phone, and the other way round, while they are connected'),
                  value: host.shareClipboard,
                  onChanged: (on) => store.saveHost(host.copyWith(shareClipboard: on)),
                ),
                const SectionHeader('Calls and quiet'),
                SwitchListTile(
                  title: const Text('Pause what is playing during calls'),
                  subtitle: Text('Music and video on ${host.title} pause when this phone rings, and carry on after the call'),
                  value: host.pauseMediaOnCalls,
                  onChanged: (on) => store.saveHost(host.copyWith(pauseMediaOnCalls: on)),
                ),
                SwitchListTile(
                  title: const Text('Do Not Disturb together'),
                  subtitle: Text('${host.title} silences its notifications while this phone is on Do Not Disturb'),
                  value: host.syncDnd,
                  onChanged: (on) => store.saveHost(host.copyWith(syncDnd: on)),
                ),
                SwitchListTile(
                  title: Text('Send text messages from ${host.title}'),
                  subtitle: const Text('Its "multiplex sms" command then sends through this phone. Off unless you want it'),
                  value: host.allowSms,
                  onChanged: _setSms,
                ),
                const SectionHeader('Notifications'),
                SwitchListTile(
                  title: Text('Show this phone\'s notifications on ${host.title}'),
                  subtitle: const Text('While they are connected. Nothing is kept on either side'),
                  value: host.mirrorNotifications,
                  onChanged: (on) => store.saveHost(host.copyWith(mirrorNotifications: on)),
                ),
                if (host.mirrorNotifications && _access == false)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 4, SettingsLayout.gutter, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const NoticeBox(
                          tone: NoticeTone.warning,
                          text: 'Android has not yet let Multiplex see notifications. Allow it under Notification access, then come back.',
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(onPressed: widget.phone.openNotificationAccess, child: const Text('Open Notification access')),
                        ),
                      ],
                    ),
                  ),
                if (host.mirrorNotifications) ...[
                  const SectionHeader('Apps'),
                  if (apps.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 12),
                      child: Text(
                        'Apps appear here as they post notifications. Switch one off to keep it on the phone only.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted),
                      ),
                    ),
                  for (final app in apps)
                    SwitchListTile(
                      title: Text(app),
                      value: !host.mutedApps.contains(app),
                      onChanged: (show) => store.saveHost(host.copyWith(mutedApps: show ? ([...host.mutedApps]..remove(app)) : [...host.mutedApps, app])),
                    ),
                ],
                if (links != null && links.received.isNotEmpty) ...[
                  const SectionHeader('Received'),
                  for (final file in links.received.where((f) => f.from == host.title))
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: MonoText(file.path, maxLines: 1),
                    ),
                ],
                const SectionHeader('On the computer'),
                for (final (command, what) in const [
                  ('multiplex send <file>', 'sends a file to this phone'),
                  ('multiplex ring', 'makes this phone ring, to find it'),
                  ('multiplex devices', 'shows its battery and whether it is connected'),
                ])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MonoText(command),
                        Text(what, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A listenable that never changes, for when there are no links.
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
