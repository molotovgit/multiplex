import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/data/models.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/ui/hosts/host_arrangement.dart';

Host _host(String id, {String? group}) => Host(id: id, label: id, address: '$id.example.com', username: 'root', groupId: group);

/// A store with groups "web" and "db" and five hosts:
/// web: w1 w2 | db: d1 | no group: x1 x2
Future<VaultStore> _store() async {
  final store = await VaultStore.open(MemoryBackend());
  store.saveGroup(const HostGroup(id: 'web', name: 'Web'));
  store.saveGroup(const HostGroup(id: 'db', name: 'Databases'));
  for (final h in [_host('w1', group: 'web'), _host('w2', group: 'web'), _host('d1', group: 'db'), _host('x1'), _host('x2')]) {
    store.saveHost(h);
  }
  return store;
}

/// The arranged rows as short labels: "#Web", "w1", ...
List<String> _rows(VaultStore store) => [
      for (final e in HostArrangement.of(store).entries)
        switch (e) {
          GroupEntry(:final title) => '#$title',
          HostEntry(:final host) => host.id,
        },
    ];

void _drop(VaultStore store, String hostId, int to) {
  final arrangement = HostArrangement.of(store);
  final from = arrangement.entries.indexWhere((e) => e is HostEntry && e.host.id == hostId);
  final order = arrangement.afterMove(from, to);
  if (order != null) store.arrangeHosts(order);
}

void main() {
  test('rows follow the saved order, grouped, with Other hosts last', () async {
    final store = await _store();
    expect(_rows(store), ['#Web', 'w1', 'w2', '#Databases', 'd1', '#Other hosts', 'x1', 'x2']);
  });

  test('dragging within a group changes the order', () async {
    final store = await _store();
    _drop(store, 'w2', 1); // to the top of Web
    expect(_rows(store), ['#Web', 'w2', 'w1', '#Databases', 'd1', '#Other hosts', 'x1', 'x2']);
  });

  test('dropping under another heading moves the host into that group', () async {
    final store = await _store();
    _drop(store, 'x2', 4); // just below the Databases heading
    expect(_rows(store), ['#Web', 'w1', 'w2', '#Databases', 'x2', 'd1', '#Other hosts', 'x1']);
    expect(store.host('x2')!.groupId, 'db');
  });

  test('a host can leave its group through the Other hosts heading', () async {
    final store = await _store();
    _drop(store, 'd1', 7); // after x1 in Other hosts (indexes after removal)
    expect(store.host('d1')!.groupId, isNull);
    expect(_rows(store).last, 'd1');
  });

  test('dropping above the first heading lands in the first group', () async {
    final store = await _store();
    _drop(store, 'x1', 0);
    expect(store.host('x1')!.groupId, 'web');
    expect(_rows(store).take(2), ['#Web', 'x1']);
  });

  test('moving a heading or dropping in place changes nothing', () async {
    final store = await _store();
    final arrangement = HostArrangement.of(store);
    expect(arrangement.afterMove(0, 3), isNull);
    expect(arrangement.afterMove(1, 1), isNull);
  });

  test('Move up and Move down stay inside the group and survive a restart', () async {
    final backend = MemoryBackend();
    final store = await VaultStore.open(backend);
    store.saveGroup(const HostGroup(id: 'web', name: 'Web'));
    for (final h in [_host('w1', group: 'web'), _host('x1'), _host('w2', group: 'web')]) {
      store.saveHost(h);
    }
    store.moveHost('w2', -1);
    store.moveHost('w2', -1); // already first in its group: no change
    store.moveHost('x1', 1); // only ungrouped host: no change
    await store.flush();
    final reopened = await VaultStore.open(backend);
    expect(_rows(reopened), ['#Web', 'w2', 'w1', '#Other hosts', 'x1']);
  });
}
