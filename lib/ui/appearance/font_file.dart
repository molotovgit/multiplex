import 'dart:typed_data';

/// What a font file says about itself: whether it is a font Flutter can
/// load, and the family name written inside it.
class FontFileInfo {
  const FontFileInfo({required this.isFont, this.family});

  /// True for a single TrueType or OpenType font.
  final bool isFont;

  /// The family name stored in the font, such as "Fira Code".
  final String? family;

  /// A font file starts with one of these four-byte markers.
  static const _trueType = 0x00010000;
  static const _appleTrue = 0x74727565; // "true"
  static const _openType = 0x4F54544F; // "OTTO"

  /// Name ids in the font's name table: the typographic family, then the
  /// plain family. The first one found is used.
  static const _nameIds = [16, 1];

  /// Reads the start of the file. Never throws: a broken file is simply
  /// "not a font".
  static FontFileInfo read(Uint8List bytes) {
    try {
      if (bytes.length < 12) return const FontFileInfo(isFont: false);
      final data = ByteData.sublistView(bytes);
      final marker = data.getUint32(0);
      if (marker != _trueType && marker != _appleTrue && marker != _openType) return const FontFileInfo(isFont: false);
      return FontFileInfo(isFont: true, family: _family(data));
    } on RangeError {
      return const FontFileInfo(isFont: false);
    }
  }

  /// Finds the "name" table and reads the family name from it.
  static String? _family(ByteData data) {
    final tables = data.getUint16(4);
    for (var i = 0; i < tables; i++) {
      final record = 12 + i * 16;
      if (data.getUint32(record) == 0x6E616D65) return _readNameTable(data, data.getUint32(record + 8)); // "name"
    }
    return null;
  }

  static String? _readNameTable(ByteData data, int table) {
    final count = data.getUint16(table + 2);
    final strings = table + data.getUint16(table + 4);
    for (final wanted in _nameIds) {
      String? fallback;
      for (var i = 0; i < count; i++) {
        final r = table + 6 + i * 12;
        if (data.getUint16(r + 6) != wanted) continue;
        final platform = data.getUint16(r);
        final language = data.getUint16(r + 4);
        final text = _decode(data, strings + data.getUint16(r + 10), data.getUint16(r + 8), utf16: platform != 1);
        if (text.isEmpty) continue;
        // English names on Windows are the most reliable; others are a fallback.
        if (platform == 3 && language == 0x409) return text;
        fallback ??= text;
      }
      if (fallback != null) return fallback;
    }
    return null;
  }

  /// Names are UTF-16 (big-endian) except on the old Mac platform, which
  /// uses one byte per letter.
  static String _decode(ByteData data, int start, int length, {required bool utf16}) {
    final codes = <int>[
      if (utf16)
        for (var i = 0; i + 1 < length; i += 2) data.getUint16(start + i)
      else
        for (var i = 0; i < length; i++) data.getUint8(start + i),
    ];
    return String.fromCharCodes(codes).replaceAll('\u0000', '').trim();
  }
}
