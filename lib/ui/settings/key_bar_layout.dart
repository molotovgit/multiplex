import '../../data/app_settings.dart';
import '../terminal/key_bar_items.dart';
import 'settings_widgets.dart';

/// The keys in the bar above the keyboard, in order, with the edits the
/// key bar editor can make. Each edit returns a new layout; nothing here
/// saves, the screen does that.
class KeyBarLayout {
  /// Keeps only known keys and drops repeats, so every key shows once.
  KeyBarLayout(List<String> ids) : ids = List.unmodifiable(_clean(ids));

  KeyBarLayout.standard() : this(AppSettings.defaultKeyBar);

  final List<String> ids;

  static List<String> _clean(List<String> ids) {
    final seen = <String>{};
    return [
      for (final id in ids)
        if (KeyBarItems.byId(id) != null && seen.add(id)) id,
    ];
  }

  List<KeyBarItem> get items => KeyBarItems.resolve(ids);

  bool get isEmpty => ids.isEmpty;

  /// Keys that could still be added, in the catalogue's order.
  List<KeyBarItem> get missing => [
        for (final item in KeyBarItems.all)
          if (!ids.contains(item.id)) item,
      ];

  /// True when the bar holds the standard keys in the standard order.
  bool get isStandard => _sameAs(KeyBarLayout.standard().ids);

  bool _sameAs(List<String> other) {
    if (other.length != ids.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (other[i] != ids[i]) return false;
    }
    return true;
  }

  /// Moves the key at [from] so it ends up at [to].
  KeyBarLayout moved(int from, int to) {
    final next = List.of(ids);
    final id = next.removeAt(from);
    next.insert(to.clamp(0, next.length), id);
    return KeyBarLayout(next);
  }

  KeyBarLayout without(String id) => KeyBarLayout([for (final k in ids) if (k != id) k]);

  /// Adds a key at the end of the bar.
  KeyBarLayout withKey(String id) => KeyBarLayout([...ids, id]);

  /// A short line for the settings list: "Esc, Tab, Ctrl and 15 more".
  String get summary {
    if (isEmpty) return 'No keys';
    const shown = 3;
    final names = items.map((i) => i.label).toList();
    if (names.length <= shown + 1) return SettingsFormat.list(names);
    return '${names.take(shown).join(', ')} and ${names.length - shown} more';
  }
}
