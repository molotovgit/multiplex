import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_settings.dart';

/// A font the terminal can use.
class TerminalFont {
  const TerminalFont({required this.id, required this.name, required this.family, this.note});

  final String id;
  final String name;

  /// Flutter font family name; null means the platform's own monospace.
  final String? family;
  final String? note;
}

/// The fonts that come with the app, plus loading of fonts the user adds.
abstract final class TerminalFonts {
  static const jetbrains = TerminalFont(
    id: 'jetbrains',
    name: 'JetBrains Mono Nerd Font',
    family: 'JetBrainsMonoNerd',
    note: 'Includes powerline and icon glyphs',
  );
  static const plex = TerminalFont(id: 'plex', name: 'IBM Plex Mono', family: 'IBMPlexMono');
  static const system = TerminalFont(id: 'system', name: 'System monospace', family: 'monospace');

  static const bundled = [jetbrains, plex, system];

  /// All fonts to offer, including the user's own.
  static List<TerminalFont> available(AppSettings settings) => [
        ...bundled,
        for (final font in settings.customFonts) TerminalFont(id: font.id, name: font.name, family: font.family, note: 'Added by you'),
      ];

  static TerminalFont byId(AppSettings settings, String id) =>
      available(settings).firstWhere((f) => f.id == id, orElse: () => jetbrains);

  /// Folder that keeps fonts the user added.
  static Future<Directory> folder() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}fonts');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Registers the user's fonts with Flutter. Call once at start-up; fonts
  /// whose file went missing are skipped.
  static Future<void> loadCustomFonts(AppSettings settings) async {
    if (settings.customFonts.isEmpty) return;
    final dir = await folder();
    for (final font in settings.customFonts) {
      await loadFile(font, File('${dir.path}${Platform.pathSeparator}${font.fileName}'));
    }
  }

  /// Registers one font file under the font's family name.
  static Future<bool> loadFile(CustomFont font, File file) async {
    if (!file.existsSync()) return false;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(font.family)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    return true;
  }
}
