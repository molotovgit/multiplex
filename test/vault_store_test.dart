import 'package:flutter_test/flutter_test.dart';
import 'package:vaultterm/data/models.dart';
import 'package:vaultterm/data/vault_backend.dart';
import 'package:vaultterm/data/vault_store.dart';
import 'package:vaultterm/src/rust/api/ssh_types.dart';
import 'package:vaultterm/src/rust/api/tunnel_types.dart';

Host _host(String id, {String? jump, String? keyId}) => Host(
      id: id,
      label: 'Host $id',
      address: '$id.example.com',
      username: 'root',
      jumpHostId: jump,
      keyId: keyId,
      authMode: keyId == null ? AuthMode.password : AuthMode.key,
    );

const _key = HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:abc', publicKey: 'ssh-ed25519 AAAA1');

void main() {
  test('a new vault starts with a few snippets and nothing else', () async {
    final store = await VaultStore.open(MemoryBackend());
    expect(store.hosts, isEmpty);
    expect(store.snippets, isNotEmpty);
  });

  test('changes are saved and survive reopening', () async {
    final backend = MemoryBackend();
    final store = await VaultStore.open(backend);
    store.saveHost(_host('a'));
    store.saveHost(_host('a').copyWith(port: 2222));
    await store.flush();
    expect(backend.saves, 1, reason: 'quick changes are written once');

    final reopened = await VaultStore.open(backend);
    expect(reopened.hosts.single.port, 2222);
    expect(reopened.hosts.single.target, 'root@a.example.com:2222');
  });

  test('deleting a host removes its tunnels and unlinks it as a jump host', () async {
    final store = await VaultStore.open(MemoryBackend());
    store.saveHost(_host('jump'));
    store.saveHost(_host('inner', jump: 'jump'));
    store.saveForward(const ForwardRule(id: 'f', hostId: 'jump', kind: TunnelKind.local, bindPort: 8080, targetPort: 80));
    store.deleteHost('jump');
    expect(store.host('inner')!.jumpHostId, isNull);
    expect(store.forwards, isEmpty);
  });

  test('deleting a key moves its hosts back to password login', () async {
    final store = await VaultStore.open(MemoryBackend());
    store.saveKey(StoredKey(id: 'k', name: 'laptop', privatePem: 'x', publicOpenssh: 'y', fingerprint: 'z', algorithm: 'ssh-ed25519', createdAt: DateTime(2026)));
    store.saveHost(_host('a', keyId: 'k'));
    store.deleteKey('k');
    expect(store.host('a')!.keyId, isNull);
    expect(store.host('a')!.authMode, AuthMode.password);
  });

  test('trusting a new key for a server replaces the old one', () async {
    final store = await VaultStore.open(MemoryBackend());
    store.trustHostKey('srv', 22, _key);
    store.trustHostKey('srv', 22, const HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:new', publicKey: 'ssh-ed25519 AAAA2'));
    expect(store.trustedKeysFor('srv', 22), ['ssh-ed25519 AAAA2']);
    expect(store.trustedKeysFor('srv', 2222), isEmpty);
  });

  test('importing a backup can merge or replace', () async {
    final source = await VaultStore.open(MemoryBackend());
    source.saveHost(_host('from-backup'));
    final backup = source.exportJson();

    final merged = await VaultStore.open(MemoryBackend());
    merged.saveHost(_host('local'));
    merged.importJson(backup, replace: false);
    expect(merged.hosts.map((h) => h.id), containsAll(['local', 'from-backup']));

    final replaced = await VaultStore.open(MemoryBackend());
    replaced.saveHost(_host('local'));
    replaced.importJson(backup, replace: true);
    expect(replaced.hosts.map((h) => h.id), ['from-backup']);
  });
}
