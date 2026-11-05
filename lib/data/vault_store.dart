import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../app/theme_spec.dart';
import '../src/rust/api/ssh_types.dart';
import 'app_settings.dart';
import 'models.dart';
import 'vault_backend.dart';
import 'vault_document.dart';

/// The app's single source of saved data. Screens read from it and call its
/// methods to change things; it saves automatically shortly after each
/// change and notifies listeners so the UI updates.
class VaultStore extends ChangeNotifier {
  VaultStore(this._backend, this._doc);

  final VaultBackend _backend;
  final VaultDocument _doc;
  Timer? _saveTimer;
  Future<void>? _saving;

  static const _uuid = Uuid();

  /// Waits this long after a change before writing, so typing in a form
  /// does not write the file on every key press.
  static const saveDelay = Duration(milliseconds: 400);

  static Future<VaultStore> open(VaultBackend backend) async {
    final json = await backend.load();
    final doc = json == null ? VaultDocument.starter() : VaultDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);
    return VaultStore(backend, doc);
  }

  static String newId() => _uuid.v4();

  // Reading.

  List<Host> get hosts => List.unmodifiable(_doc.hosts);
  List<HostGroup> get groups => List.unmodifiable(_doc.groups);
  List<StoredKey> get keys => List.unmodifiable(_doc.keys);
  List<Snippet> get snippets => List.unmodifiable(_doc.snippets);
  List<KnownHost> get knownHosts => List.unmodifiable(_doc.knownHosts);
  List<ForwardRule> get forwards => List.unmodifiable(_doc.forwards);
  AppSettings get settings => _doc.settings;
  List<ThemeSpec> get customThemes => List.unmodifiable(_doc.customThemes);

  /// Built-in themes first, then the user's own.
  List<ThemeSpec> get allThemes => [...BuiltInThemes.all, ..._doc.customThemes];

  /// The theme in use. Falls back to the default if it was deleted.
  ThemeSpec get activeTheme => themeById(_doc.settings.themeId);

  ThemeSpec themeById(String id) => _find(allThemes, (t) => t.id == id) ?? BuiltInThemes.ember;

  Host? host(String? id) => _find(_doc.hosts, (h) => h.id == id);
  StoredKey? key(String? id) => _find(_doc.keys, (k) => k.id == id);
  HostGroup? group(String? id) => _find(_doc.groups, (g) => g.id == id);
  List<ForwardRule> forwardsFor(String hostId) => _doc.forwards.where((f) => f.hostId == hostId).toList();

  /// Host keys already accepted for this address and port.
  List<String> trustedKeysFor(String host, int port) =>
      _doc.knownHosts.where((k) => k.host == host && k.port == port).map((k) => k.publicKey).toList();

  // Hosts and groups.

  void saveHost(Host host) => _upsert(_doc.hosts, host, (h) => h.id);

  /// Deletes a host with its saved tunnels, and unlinks it where it was
  /// used as a jump host.
  void deleteHost(String id) {
    _doc.hosts.removeWhere((h) => h.id == id);
    _doc.forwards.removeWhere((f) => f.hostId == id);
    _replaceWhere(_doc.hosts, (h) => h.jumpHostId == id, (h) => h.copyWith(jumpHostId: () => null));
    _changed();
  }

  void markConnected(String hostId) {
    _replaceWhere(_doc.hosts, (h) => h.id == hostId, (h) => h.copyWith(lastConnectedAt: DateTime.now()));
    _changed();
  }

  void saveGroup(HostGroup group) => _upsert(_doc.groups, group, (g) => g.id);

  /// Deletes a group; its hosts move to "no group".
  void deleteGroup(String id) {
    _doc.groups.removeWhere((g) => g.id == id);
    _replaceWhere(_doc.hosts, (h) => h.groupId == id, (h) => h.copyWith(groupId: () => null));
    _changed();
  }

  // Keys, snippets, known hosts, tunnels.

  void saveKey(StoredKey key) => _upsert(_doc.keys, key, (k) => k.id);

  /// Deletes a key; hosts that used it fall back to password login.
  void deleteKey(String id) {
    _doc.keys.removeWhere((k) => k.id == id);
    _replaceWhere(_doc.hosts, (h) => h.keyId == id, (h) => h.copyWith(keyId: () => null, authMode: AuthMode.password));
    _changed();
  }

  void saveSnippet(Snippet snippet) => _upsert(_doc.snippets, snippet, (s) => s.id);

  void deleteSnippet(String id) {
    _doc.snippets.removeWhere((s) => s.id == id);
    _changed();
  }

  /// Remembers a server key. Any older key for the same address and port
  /// is replaced, which is what the user wants after confirming a change.
  void trustHostKey(String host, int port, HostKeyInfo key) {
    _doc.knownHosts.removeWhere((k) => k.host == host && k.port == port);
    _doc.knownHosts.add(KnownHost(
      host: host,
      port: port,
      publicKey: key.publicKey,
      fingerprint: key.fingerprint,
      algorithm: key.algorithm,
      addedAt: DateTime.now(),
    ));
    _changed();
  }

  void forgetKnownHost(KnownHost known) {
    _doc.knownHosts.removeWhere((k) => k.endpoint == known.endpoint && k.publicKey == known.publicKey);
    _changed();
  }

  void saveForward(ForwardRule rule) => _upsert(_doc.forwards, rule, (f) => f.id);

  void deleteForward(String id) {
    _doc.forwards.removeWhere((f) => f.id == id);
    _changed();
  }

  /// Adds or updates a custom theme.
  void saveTheme(ThemeSpec theme) => _upsert(_doc.customThemes, theme, (t) => t.id);

  /// Deletes a custom theme; if it was in use, the default comes back.
  void deleteTheme(String id) {
    _doc.customThemes.removeWhere((t) => t.id == id);
    if (_doc.settings.themeId == id) {
      _doc.settings = _doc.settings.copyWith(themeId: BuiltInThemes.defaultId);
    }
    _changed();
  }

  void updateSettings(AppSettings settings) {
    _doc.settings = settings;
    _changed();
  }

  // Backups.

  /// The whole vault as JSON, for an encrypted backup.
  String exportJson() => jsonEncode(_doc.toJson());

  /// Brings in a backup. `replace` wipes current data first; otherwise
  /// items with the same id are overwritten and the rest is kept.
  void importJson(String json, {required bool replace}) {
    final incoming = VaultDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);
    if (replace) {
      _doc
        ..hosts.clear()
        ..groups.clear()
        ..keys.clear()
        ..snippets.clear()
        ..knownHosts.clear()
        ..forwards.clear()
        ..customThemes.clear();
      _doc.settings = incoming.settings;
    }
    _doc.mergeFrom(incoming);
    _changed();
  }

  /// Writes any pending change now (for example when the app goes to the
  /// background).
  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _write();
    }
    await _saving;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _upsert<T>(List<T> list, T item, String Function(T) idOf) {
    final index = list.indexWhere((e) => idOf(e) == idOf(item));
    if (index >= 0) {
      list[index] = item;
    } else {
      list.add(item);
    }
    _changed();
  }

  static void _replaceWhere<T>(List<T> list, bool Function(T) test, T Function(T) change) {
    for (var i = 0; i < list.length; i++) {
      if (test(list[i])) list[i] = change(list[i]);
    }
  }

  static T? _find<T>(List<T> list, bool Function(T) test) {
    for (final item in list) {
      if (test(item)) return item;
    }
    return null;
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, _write);
  }

  Future<void> _write() {
    final json = exportJson();
    // Chain writes so two saves never overlap on disk.
    final previous = _saving ?? Future.value();
    final next = previous.then((_) => _backend.save(json));
    _saving = next.catchError((Object e) => debugPrint('VaultTerm: saving failed: $e'));
    return _saving!;
  }
}
