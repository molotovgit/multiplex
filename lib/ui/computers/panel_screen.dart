import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../../sessions/desk_controller.dart';
import '../../sessions/session_manager.dart';
import '../hosts/host_connector.dart';
import '../settings/settings_widgets.dart';
import 'omarchy_panel.dart';

/// A computer's panel as a page of its own: steer the desktop without
/// looking at it.
class PanelScreen extends StatefulWidget {
  const PanelScreen({super.key, required this.session, this.link});

  final LiveSession session;

  /// Tests pass a stand-in.
  final DeskLink? link;

  /// Connects (if needed) and opens the panel.
  static Future<void> open(BuildContext context, Host host) async {
    final session = await HostConnector.connect(context, host);
    if (session == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PanelScreen(session: session)));
  }

  @override
  State<PanelScreen> createState() => _PanelScreenState();
}

class _PanelScreenState extends State<PanelScreen> {
  late final DeskController _desk = DeskController(widget.link ?? SshDeskLink(() => widget.session.ssh))..start();

  @override
  void dispose() {
    _desk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.watch(context);
    // The saved computer, so pins show as they change.
    final host = store.host(widget.session.host.id) ?? widget.session.host;
    return Scaffold(
      appBar: AppBar(title: Text('${host.title} panel')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 24),
          children: [
            OmarchyPanel(
              controller: _desk,
              pins: host.pins,
              onPinsChanged: (pins) {
                if (store.host(host.id) != null) store.saveHost(host.copyWith(pins: pins));
              },
            ),
          ],
        ),
      ),
    );
  }
}
