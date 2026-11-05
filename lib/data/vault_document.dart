import 'app_settings.dart';
import 'models.dart';

/// The whole saved state of the app, as one JSON document. It is written
/// encrypted to disk by [VaultStore] and also used for backups.
class VaultDocument {
  VaultDocument({
    List<Host>? hosts,
    List<HostGroup>? groups,
    List<StoredKey>? keys,
    List<Snippet>? snippets,
    List<KnownHost>? knownHosts,
    List<ForwardRule>? forwards,
    this.settings = const AppSettings(),
  })  // Always keep our own growable copies, so constant lists passed in
      // (such as the starter snippets) can still be edited later.
      : hosts = List.of(hosts ?? const []),
        groups = List.of(groups ?? const []),
        keys = List.of(keys ?? const []),
        snippets = List.of(snippets ?? const []),
        knownHosts = List.of(knownHosts ?? const []),
        forwards = List.of(forwards ?? const []);

  /// Bumped when the format changes in a way old versions cannot read.
  static const formatVersion = 1;

  final List<Host> hosts;
  final List<HostGroup> groups;
  final List<StoredKey> keys;
  final List<Snippet> snippets;
  final List<KnownHost> knownHosts;
  final List<ForwardRule> forwards;
  AppSettings settings;

  /// A few handy commands so the snippets list is not empty on day one.
  factory VaultDocument.starter() => VaultDocument(snippets: const [
        Snippet(id: 'starter-disk', name: 'Disk usage', command: 'df -h'),
        Snippet(id: 'starter-mem', name: 'Memory', command: 'free -h'),
        Snippet(id: 'starter-top', name: 'Top processes', command: 'top'),
        Snippet(id: 'starter-logs', name: 'Recent system log', command: 'journalctl -n 100 --no-pager'),
      ]);

  Map<String, dynamic> toJson() => {
        'format': formatVersion,
        'hosts': hosts.map((e) => e.toJson()).toList(),
        'groups': groups.map((e) => e.toJson()).toList(),
        'keys': keys.map((e) => e.toJson()).toList(),
        'snippets': snippets.map((e) => e.toJson()).toList(),
        'knownHosts': knownHosts.map((e) => e.toJson()).toList(),
        'forwards': forwards.map((e) => e.toJson()).toList(),
        'settings': settings.toJson(),
      };

  factory VaultDocument.fromJson(Map<String, dynamic> j) => VaultDocument(
        hosts: Json.list(j, 'hosts').map(Host.fromJson).toList(),
        groups: Json.list(j, 'groups').map(HostGroup.fromJson).toList(),
        keys: Json.list(j, 'keys').map(StoredKey.fromJson).toList(),
        snippets: Json.list(j, 'snippets').map(Snippet.fromJson).toList(),
        knownHosts: Json.list(j, 'knownHosts').map(KnownHost.fromJson).toList(),
        forwards: Json.list(j, 'forwards').map(ForwardRule.fromJson).toList(),
        settings: j['settings'] is Map ? AppSettings.fromJson((j['settings'] as Map).cast<String, dynamic>()) : const AppSettings(),
      );

  /// Adds everything from [other], replacing items with the same id (or,
  /// for known hosts, the same host and port). Used when importing a
  /// backup without wiping what is already here.
  void mergeFrom(VaultDocument other) {
    _mergeById(hosts, other.hosts, (e) => e.id);
    _mergeById(groups, other.groups, (e) => e.id);
    _mergeById(keys, other.keys, (e) => e.id);
    _mergeById(snippets, other.snippets, (e) => e.id);
    _mergeById(knownHosts, other.knownHosts, (e) => '${e.endpoint} ${e.publicKey}');
    _mergeById(forwards, other.forwards, (e) => e.id);
  }

  static void _mergeById<T>(List<T> into, List<T> from, String Function(T) idOf) {
    for (final item in from) {
      final index = into.indexWhere((e) => idOf(e) == idOf(item));
      if (index >= 0) {
        into[index] = item;
      } else {
        into.add(item);
      }
    }
  }
}
