import 'models.dart';

/// One command the user ran on a host.
class HistoryEntry {
  const HistoryEntry({required this.command, required this.lastUsed, this.pinned = false, this.uses = 1});

  final String command;

  /// When it last ran.
  final DateTime lastUsed;

  /// Pinned commands come first and are never dropped by the cap.
  final bool pinned;

  /// How many times it ran.
  final int uses;

  HistoryEntry copyWith({DateTime? lastUsed, bool? pinned, int? uses}) =>
      HistoryEntry(command: command, lastUsed: lastUsed ?? this.lastUsed, pinned: pinned ?? this.pinned, uses: uses ?? this.uses);

  Map<String, dynamic> toJson() => {'command': command, 'lastUsed': lastUsed.toIso8601String(), 'pinned': pinned, 'uses': uses};

  /// Null when the entry has no command (a damaged or foreign file).
  static HistoryEntry? fromJson(Map<String, dynamic> j) {
    final command = Json.str(j, 'command').trim();
    if (command.isEmpty) return null;
    return HistoryEntry(
      command: command,
      lastUsed: Json.time(j, 'lastUsed') ?? DateTime.fromMillisecondsSinceEpoch(0),
      pinned: Json.boolean(j, 'pinned', false),
      uses: Json.integer(j, 'uses', 1).clamp(1, 1 << 30),
    );
  }
}

/// Recent commands per host: newest first, at most [maxPerHost] each.
/// Running a command again moves it to the top.
class CommandHistory {
  CommandHistory([Map<String, List<HistoryEntry>>? byHost]) : _byHost = {for (final e in (byHost ?? const {}).entries) e.key: List.of(e.value)};

  static const maxPerHost = 200;

  /// Longer lines are not commands worth keeping (a pasted file, say).
  static const maxLength = 2000;

  final Map<String, List<HistoryEntry>> _byHost;

  /// The host ids that have history.
  Iterable<String> get hosts => _byHost.keys;

  /// Newest first, pinned or not.
  List<HistoryEntry> recent(String hostId) => List.unmodifiable(_byHost[hostId] ?? const []);

  /// Pinned commands first, then the rest; each group newest first.
  List<HistoryEntry> ordered(String hostId) {
    final all = _byHost[hostId] ?? const <HistoryEntry>[];
    return [...all.where((e) => e.pinned), ...all.where((e) => !e.pinned)];
  }

  /// Commands for the strip while the user types [typed]: those that
  /// start with it first, then those that contain it. Case is ignored.
  /// Pinned commands lead each group.
  List<HistoryEntry> suggest(String hostId, String typed) {
    final query = typed.trim().toLowerCase();
    final all = ordered(hostId);
    if (query.isEmpty) return all;
    final starts = <HistoryEntry>[];
    final contains = <HistoryEntry>[];
    for (final e in all) {
      final c = e.command.toLowerCase();
      if (c == query) continue;
      if (c.startsWith(query)) {
        starts.add(e);
      } else if (c.contains(query)) {
        contains.add(e);
      }
    }
    return [...starts, ...contains];
  }

  /// For the history sheet's search box.
  List<HistoryEntry> search(String hostId, String query) {
    final q = query.trim().toLowerCase();
    final all = ordered(hostId);
    return q.isEmpty ? all : all.where((e) => e.command.toLowerCase().contains(q)).toList();
  }

  /// Adds a command at the top. Returns false when it was not kept
  /// (empty or too long).
  bool record(String hostId, String command, {DateTime? at}) {
    final clean = command.trim();
    if (clean.isEmpty || clean.length > maxLength) return false;
    final list = _byHost.putIfAbsent(hostId, () => []);
    final index = list.indexWhere((e) => e.command == clean);
    final old = index >= 0 ? list.removeAt(index) : null;
    final when = at ?? DateTime.now();
    list.insert(0, old?.copyWith(lastUsed: when, uses: old.uses + 1) ?? HistoryEntry(command: clean, lastUsed: when));
    _cap(list);
    return true;
  }

  void setPinned(String hostId, String command, bool pinned) {
    final list = _byHost[hostId];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      if (list[i].command == command) list[i] = list[i].copyWith(pinned: pinned);
    }
  }

  void delete(String hostId, String command) {
    final list = _byHost[hostId];
    if (list == null) return;
    list.removeWhere((e) => e.command == command);
    if (list.isEmpty) _byHost.remove(hostId);
  }

  /// Forgets every command of the host, pinned ones too.
  void clear(String hostId) => _byHost.remove(hostId);

  /// Adds the history from a backup. Commands both sides know keep the
  /// newer use time and stay pinned if either side pinned them.
  void mergeFrom(CommandHistory other) {
    for (final hostId in other._byHost.keys) {
      final mine = {for (final e in _byHost[hostId] ?? const <HistoryEntry>[]) e.command: e};
      for (final e in other._byHost[hostId]!) {
        final have = mine[e.command];
        mine[e.command] = have == null
            ? e
            : (e.lastUsed.isAfter(have.lastUsed) ? e : have).copyWith(pinned: e.pinned || have.pinned, uses: have.uses > e.uses ? have.uses : e.uses);
      }
      final merged = mine.values.toList()..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      _cap(merged);
      _byHost[hostId] = merged;
    }
  }

  /// Drops the oldest unpinned commands beyond the cap. Pinned commands
  /// are only dropped when nothing else is left to drop.
  static void _cap(List<HistoryEntry> list) {
    while (list.length > maxPerHost) {
      final oldestUnpinned = list.lastIndexWhere((e) => !e.pinned);
      list.removeAt(oldestUnpinned >= 0 ? oldestUnpinned : list.length - 1);
    }
  }

  Map<String, dynamic> toJson() => {
        for (final e in _byHost.entries)
          if (e.value.isNotEmpty) e.key: [for (final h in e.value) h.toJson()],
      };

  /// Reads what [toJson] wrote. Anything unexpected is skipped, so a
  /// damaged entry never stops the vault from opening.
  factory CommandHistory.fromJson(Object? json) {
    final byHost = <String, List<HistoryEntry>>{};
    if (json is Map) {
      for (final e in json.entries) {
        if (e.key is! String || e.value is! List) continue;
        final seen = <String>{};
        final list = <HistoryEntry>[
          for (final item in e.value as List)
            if (item is Map)
              if (HistoryEntry.fromJson(item.cast<String, dynamic>()) case final entry? when seen.add(entry.command)) entry,
        ];
        _cap(list);
        if (list.isNotEmpty) byHost[e.key as String] = list;
      }
    }
    return CommandHistory(byHost);
  }
}
