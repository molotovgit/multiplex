import 'package:flutter/foundation.dart';

import '../ui/desktop/desktop_keys.dart';

/// A sticky modifier on the key bar: off, on for the next key, or locked.
enum ModState { off, once, locked }

/// Something on the computer that takes keys: the remote desktop, or the
/// touchpad without a picture. The key bar and Multiplex's keyboard type
/// into either.
abstract interface class KeyTarget implements Listenable {
  /// Sticky modifiers from the key bar.
  Map<int, ModState> get mods;

  void toggleMod(int code);

  /// Taps a key with the sticky modifiers (and [extra] ones) held.
  void tap(int code, {List<int> extra});

  /// Raw press or release, for a hardware keyboard.
  void keyEvent(int code, bool pressed);

  /// Types text.
  void type(String text);

  /// Sends the phone's clipboard and pastes it. False when it is empty.
  Future<bool> pastePhoneClipboard();
}

/// The sticky modifiers of a key bar: Super, Ctrl, Alt and Shift, each
/// off, on for the next key, or locked.
mixin StickyMods on ChangeNotifier {
  final Map<int, ModState> mods = {
    LinuxKey.leftMeta: ModState.off,
    LinuxKey.leftCtrl: ModState.off,
    LinuxKey.leftAlt: ModState.off,
    LinuxKey.leftShift: ModState.off,
  };
  final Map<int, DateTime> _modTapped = {};

  /// One tap: on for the next key; a quick second tap: locked; a tap
  /// while on or locked: off.
  void toggleMod(int code) {
    final now = DateTime.now();
    final last = _modTapped[code];
    _modTapped[code] = now;
    final state = mods[code] ?? ModState.off;
    final quick = last != null && now.difference(last) < const Duration(milliseconds: 350);
    mods[code] = switch (state) {
      ModState.off => ModState.once,
      ModState.once => quick ? ModState.locked : ModState.off,
      ModState.locked => ModState.off,
    };
    notifyListeners();
  }

  /// The modifiers that are on or locked.
  List<int> activeMods() => [
    for (final e in mods.entries)
      if (e.value != ModState.off) e.key,
  ];

  /// After a key: modifiers that were on for one key go off.
  void consumeOnceMods() {
    var changed = false;
    for (final e in mods.entries.toList()) {
      if (e.value == ModState.once) {
        mods[e.key] = ModState.off;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
