import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/vault_store.dart';

/// Keeps Android's share sheet current: each paired computer is offered
/// there by name, so sharing to it is one tap from any app. Only its id
/// and name leave the vault. Other platforms ignore it.
class ShareTargetsSync {
  ShareTargetsSync(this._store, {MethodChannel channel = const MethodChannel('multiplex/share_targets')})
    // ignore: prefer_initializing_formals
    : _channel = channel {
    _store.addListener(_update);
    _update();
  }

  final VaultStore _store;
  final MethodChannel _channel;
  String? _lastSent;

  /// The paired computers, as the native side takes them.
  static List<Map<String, String>> payload(List<Host> hosts) => [
    for (final h in hosts.where((h) => h.computer)) {'id': h.id, 'label': h.title},
  ];

  void _update() {
    final targets = payload(_store.hosts);
    final key = jsonEncode(targets);
    if (key == _lastSent) return;
    _lastSent = key;
    _send(targets);
  }

  Future<void> _send(List<Map<String, String>> targets) async {
    try {
      await _channel.invokeMethod<void>('set', targets);
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // A convenience: the share screen still lists the computers.
    }
  }
}
