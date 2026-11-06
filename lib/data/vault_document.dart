import '../app/theme_spec.dart';
import 'app_settings.dart';
import 'command_history.dart';
import 'models.dart';
import 'otp_account.dart';
import 'sync_pairs.dart';

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
    List<ThemeSpec>? customThemes,
    this.settings = const AppSettings(),
    CommandHistory? commandHistory,
    List<OtpAccount>? otpAccounts,
    List<SyncPair>? syncPairs,
  })  // Always keep our own growable copies, so constant lists passed in
      // (such as the starter snippets) can still be edited later.
      : hosts = List.of(hosts ?? const []),
        groups = List.of(groups ?? const []),
        keys = List.of(keys ?? const []),
        snippets = List.of(snippets ?? const []),
        knownHosts = List.of(knownHosts ?? const []),
        forwards = List.of(forwards ?? const []),
        customThemes = List.of(customThemes ?? const []),
        commandHistory = commandHistory ?? CommandHistory(),
        otpAccounts = List.of(otpAccounts ?? const []),
        syncPairs = List.of(syncPairs ?? const []);

  /// Bumped when the format changes in a way old versions cannot read.
  static const formatVersion = 1;

  final List<Host> hosts;
  final List<HostGroup> groups;
  final List<StoredKey> keys;
  final List<Snippet> snippets;
  final List<KnownHost> knownHosts;
  final List<ForwardRule> forwards;

  /// Themes the user made or imported.
  final List<ThemeSpec> customThemes;
  AppSettings settings;

  /// Recent commands per host, for the keyboard's suggestions.
  CommandHistory commandHistory;

  /// One-time code accounts (the Codes tab).
  final List<OtpAccount> otpAccounts;
  /// Phone and server folders kept in step, per host.
  final List<SyncPair> syncPairs;

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
        'customThemes': customThemes.map((e) => e.toJson()).toList(),
        'settings': settings.toJson(),
        'commandHistory': commandHistory.toJson(),
        'otpAccounts': otpAccounts.map((e) => e.toJson()).toList(),
        'syncPairs': syncPairs.map((e) => e.toJson()).toList(),
      };

  factory VaultDocument.fromJson(Map<String, dynamic> j) => VaultDocument(
        hosts: Json.list(j, 'hosts').map(Host.fromJson).toList(),
        groups: Json.list(j, 'groups').map(HostGroup.fromJson).toList(),
        keys: Json.list(j, 'keys').map(StoredKey.fromJson).toList(),
        snippets: Json.list(j, 'snippets').map(Snippet.fromJson).toList(),
        knownHosts: Json.list(j, 'knownHosts').map(KnownHost.fromJson).toList(),
        forwards: Json.list(j, 'forwards').map(ForwardRule.fromJson).toList(),
        customThemes: Json.list(j, 'customThemes').map(ThemeSpec.fromJson).toList(),
        settings: j['settings'] is Map ? AppSettings.fromJson((j['settings'] as Map).cast<String, dynamic>()) : const AppSettings(),
        commandHistory: CommandHistory.fromJson(j['commandHistory']),
        otpAccounts: Json.list(j, 'otpAccounts').map(OtpAccount.fromJson).toList(),
        syncPairs: Json.list(j, 'syncPairs').map(SyncPair.fromJson).toList(),
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
    _mergeById(customThemes, other.customThemes, (e) => e.id);
    _mergeById(otpAccounts, other.otpAccounts, (e) => e.id);
    commandHistory.mergeFrom(other.commandHistory);
    _mergeById(syncPairs, other.syncPairs, (e) => e.id);
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
