import '../../data/models.dart';
import '../../data/vault_store.dart';

/// One row of the arranged host list: a group heading or a host.
sealed class HostListEntry {
  const HostListEntry();

  /// Stable key for the reorderable list.
  String get key;
}

/// A heading. [groupId] is null for the "Other hosts" section.
class GroupEntry extends HostListEntry {
  const GroupEntry(this.group, this.title);

  final HostGroup? group;
  final String title;

  String? get groupId => group?.id;

  @override
  String get key => 'group:${groupId ?? '-'}';
}

class HostEntry extends HostListEntry {
  const HostEntry(this.host);

  final Host host;

  @override
  String get key => 'host:${host.id}';
}

/// Works out the rows of the host list in the user's own order, and what a
/// drag and drop means: the host takes the new place and joins the group
/// whose heading is above it.
class HostArrangement {
  HostArrangement(this.entries);

  final List<HostListEntry> entries;

  /// Groups in the order they were made, each followed by its hosts in the
  /// user's order, then the hosts without a group.
  factory HostArrangement.of(VaultStore store) {
    final hosts = store.hosts;
    final groups = store.groups;
    final entries = <HostListEntry>[];
    for (final group in groups) {
      entries.add(GroupEntry(group, group.name));
      entries.addAll(hosts.where((h) => h.groupId == group.id).map(HostEntry.new));
    }
    final ungrouped = hosts.where((h) => store.group(h.groupId) == null).toList();
    // With groups around, the "Other hosts" heading stays visible even when
    // empty, so a host can be dragged out of its group.
    if (ungrouped.isNotEmpty || groups.isNotEmpty) {
      entries.add(GroupEntry(null, groups.isEmpty ? 'All hosts' : 'Other hosts'));
      entries.addAll(ungrouped.map(HostEntry.new));
    }
    return HostArrangement(entries);
  }

  /// The new order after the row at [from] was dropped so that it ends up
  /// at index [to] (as Flutter's onReorderItem reports it). Returns null when
  /// the drop changes nothing, for example when a heading was moved.
  List<({String id, String? groupId})>? afterMove(int from, int to) {
    if (from < 0 || from >= entries.length || entries[from] is! HostEntry) return null;
    var target = to;
    final rows = [...entries];
    final moved = rows.removeAt(from);
    target = target.clamp(0, rows.length);
    // Above the first heading still means "the first section".
    if (target == 0 && rows.isNotEmpty && rows.first is GroupEntry) target = 1;
    rows.insert(target, moved);

    String? group;
    final order = <({String id, String? groupId})>[];
    for (final row in rows) {
      switch (row) {
        case GroupEntry(:final groupId):
          group = groupId;
        case HostEntry(:final host):
          order.add((id: host.id, groupId: group));
      }
    }
    final before = [
      for (final e in entries)
        if (e is HostEntry) (id: e.host.id, groupId: e.host.groupId),
    ];
    return _same(before, order) ? null : order;
  }

  static bool _same(List<({String id, String? groupId})> a, List<({String id, String? groupId})> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
