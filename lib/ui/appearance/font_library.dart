import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../app/terminal_fonts.dart';
import '../../data/app_settings.dart';
import '../../data/vault_store.dart';
import 'font_file.dart';
import 'theme_import.dart';

/// Something is wrong with a font file the user picked. The message is
/// written for the user.
class FontFileException implements Exception {
  const FontFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Adds fonts the user brings from files, and removes them again.
///
/// The file is copied into [TerminalFonts.folder] under a name of its own,
/// so two fonts with the same file name never clash, and the font list in
/// the settings records it.
class FontLibrary {
  FontLibrary(this.store);

  final VaultStore store;

  static const extensions = ['ttf', 'otf'];

  /// Big enough for fonts with many scripts, small enough to load quickly.
  static const maxBytes = 50 * 1024 * 1024;

  /// Phones do not filter reliably by font file type, so there every file
  /// is shown and the type is checked after picking.
  static FileType get _pickerType => Platform.isAndroid || Platform.isIOS ? FileType.any : FileType.custom;

  /// Lets the user pick a font file, keeps a copy, loads it and makes it
  /// the terminal font. Returns null when the user cancels.
  Future<CustomFont?> addFromFile() async {
    final type = _pickerType;
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Add font',
      type: type,
      allowedExtensions: type == FileType.custom ? extensions : null,
    );
    if (picked == null) return null;

    final extension = (picked.extension ?? '').toLowerCase();
    if (!extensions.contains(extension)) {
      throw FontFileException('"${picked.name}" is not a font file. Pick a .ttf or .otf file.');
    }
    final size = picked.lengthSync() ?? await picked.length();
    if (size != null && size > maxBytes) {
      throw FontFileException('"${picked.name}" is larger than 50 MB. Pick a smaller font file.');
    }
    final bytes = await picked.readAsBytes();
    final info = FontFileInfo.read(bytes);
    if (!info.isFont) {
      throw FontFileException('"${picked.name}" is not a font Multiplex can use. Pick a TrueType (.ttf) or OpenType (.otf) font.');
    }

    final id = VaultStore.newId();
    final font = CustomFont(
      id: id,
      name: info.family ?? ThemeSourceName.fromFileName(picked.name) ?? 'My font',
      fileName: '$id.$extension',
    );
    final file = await _fileOf(font);
    await file.writeAsBytes(bytes, flush: true);
    var loaded = false;
    try {
      loaded = await TerminalFonts.loadFile(font, file);
    } catch (_) {
      // Flutter could not read the font; handled just below.
    }
    if (!loaded) {
      await _deleteQuietly(file);
      throw FontFileException('"${picked.name}" could not be loaded. Pick another font file.');
    }

    final settings = store.settings;
    store.updateSettings(settings.copyWith(customFonts: [...settings.customFonts, font], terminalFontId: font.id));
    return font;
  }

  /// Takes the font off the list and deletes its file. When it was the
  /// terminal font, the bundled Nerd Font is used again.
  Future<void> remove(CustomFont font) async {
    final settings = store.settings;
    store.updateSettings(settings.copyWith(
      customFonts: [for (final f in settings.customFonts) if (f.id != font.id) f],
      terminalFontId: settings.terminalFontId == font.id ? TerminalFonts.jetbrains.id : null,
    ));
    await _deleteQuietly(await _fileOf(font));
  }

  Future<File> _fileOf(CustomFont font) async {
    final dir = await TerminalFonts.folder();
    return File('${dir.path}${Platform.pathSeparator}${font.fileName}');
  }

  /// A leftover file does no harm, so a failed delete is not reported.
  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Ignored on purpose; see above.
    }
  }
}
