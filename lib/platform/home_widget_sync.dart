import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/vault_store.dart';

/// Keeps the Android home-screen widget's list of favourite hosts up to
/// date. Only each host's id and name go to the widget, never an address,
/// a login or a password. Other platforms ignore it.
class HomeWidgetSync {
  HomeWidgetSync(this._store) {
    _store.addListener(_update);
    _update();
  }

  /// The widget has room for this many hosts.
  static const maxHosts = 4;

  static const _channel = MethodChannel('multiplex/widget');

  final VaultStore _store;

  /// The last list sent, so the widget is only redrawn on real changes.
  String? _lastSent;

  /// The favourites in the order of the hosts list, as the small JSON the
  /// widget reads: `[{"id": "...", "label": "..."}]`.
  static String payload(List<Host> hosts) => jsonEncode([
    for (final h in hosts.where((h) => h.favourite).take(maxHosts)) {'id': h.id, 'label': h.title},
  ]);

  void _update() {
    final json = payload(_store.hosts);
    if (json == _lastSent) return;
    _lastSent = json;
    _send(json);
  }

  Future<void> _send(String json) async {
    try {
      await _channel.invokeMethod<void>('setFavourites', {'json': json});
    } on MissingPluginException {
      // Desktop and iOS builds have no widget.
    } on PlatformException {
      // Never let the widget break saving.
    }
  }

  void dispose() => _store.removeListener(_update);
}
