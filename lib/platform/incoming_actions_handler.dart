import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../ui/common/widgets.dart';
import '../ui/hosts/host_connector.dart';
import '../ui/share/share_upload_screen.dart';
import 'incoming_actions.dart';

/// Carries out what Android asks from outside the app (see
/// [IncomingAction]). It sits below the app lock, so nothing happens
/// before the app is unlocked; actions that came in earlier wait.
class IncomingActionsHandler extends StatefulWidget {
  const IncomingActionsHandler({super.key, required this.child, this.channel});

  final Widget child;

  /// Replaced in tests.
  final IncomingChannel? channel;

  @override
  State<IncomingActionsHandler> createState() => _IncomingActionsHandlerState();
}

class _IncomingActionsHandlerState extends State<IncomingActionsHandler> {
  late final IncomingChannel _channel = widget.channel ?? IncomingChannel();

  @override
  void initState() {
    super.initState();
    _channel.listen(_takeAll);
    // Whatever opened the app (a widget tap, a share) is already waiting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeAll());
  }

  @override
  void dispose() {
    _channel.stop();
    super.dispose();
  }

  Future<void> _takeAll() async {
    for (final action in await _channel.take()) {
      if (!mounted) return;
      // Not awaited: each action opens a page, which only completes when
      // the user leaves it.
      unawaited(_handle(action));
    }
  }

  Future<void> _handle(IncomingAction action) async {
    switch (action) {
      case ConnectAction(:final hostId):
        final host = AppScope.store(context).host(hostId);
        if (host == null) {
          Toast.show(context, 'That host is no longer saved in Multiplex.');
          return;
        }
        await HostConnector.openTerminal(context, host);
      case ShareAction(:final files):
        await ShareUploadScreen.open(context, files);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
