import 'models.dart';

/// Which way a sync pair copies, as saved in the vault.
enum SyncWay {
  /// Phone to server: the phone folder is the source.
  toServer('Phone to server'),

  /// Server to phone.
  toPhone('Server to phone'),

  /// Both ways: the newer copy of each file wins.
  both('Both ways, newer wins');

  const SyncWay(this.label);

  final String label;
}

/// A phone folder and a server folder kept in step, saved per host.
class SyncPair {
  const SyncPair({
    required this.id,
    required this.hostId,
    required this.name,
    required this.phonePath,
    required this.serverPath,
    this.way = SyncWay.toServer,
    this.mirror = false,
    this.lastSyncedAt,
  });

  final String id;
  final String hostId;
  final String name;
  final String phonePath;
  final String serverPath;
  final SyncWay way;

  /// Deletes what the source side lacks. Only for one-way pairs, and only
  /// when the user ticked it and confirmed.
  final bool mirror;
  final DateTime? lastSyncedAt;

  /// Mirror never applies to two-way syncs, whatever was saved.
  bool get mirrors => mirror && way != SyncWay.both;

  SyncPair copyWith({String? name, String? phonePath, String? serverPath, SyncWay? way, bool? mirror, DateTime? lastSyncedAt}) => SyncPair(
    id: id,
    hostId: hostId,
    name: name ?? this.name,
    phonePath: phonePath ?? this.phonePath,
    serverPath: serverPath ?? this.serverPath,
    way: way ?? this.way,
    mirror: mirror ?? this.mirror,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'hostId': hostId,
    'name': name,
    'phonePath': phonePath,
    'serverPath': serverPath,
    'way': way.name,
    'mirror': mirror,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };

  factory SyncPair.fromJson(Map<String, dynamic> j) => SyncPair(
    id: Json.str(j, 'id'),
    hostId: Json.str(j, 'hostId'),
    name: Json.str(j, 'name', 'Sync'),
    phonePath: Json.str(j, 'phonePath'),
    serverPath: Json.str(j, 'serverPath'),
    way: SyncWay.values.asNameMap()[j['way']] ?? SyncWay.toServer,
    mirror: Json.boolean(j, 'mirror', false),
    lastSyncedAt: Json.time(j, 'lastSyncedAt'),
  );
}
