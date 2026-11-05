import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/theme_backgrounds.dart';
import 'package:multiplex/app/theme_spec.dart';
import 'package:multiplex/ui/appearance/theme_import.dart';
import 'package:multiplex/ui/appearance/theme_pack_file.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('packfile');
    ThemeBackgrounds.rootOverride = root;
  });
  tearDown(() {
    ThemeBackgrounds.rootOverride = null;
    root.deleteSync(recursive: true);
  });

  Uint8List png(int marker) => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, marker]);

  Future<ThemeSpec> themeWithPictures() async {
    final a = await ThemeBackgrounds.addBytes('mine', png(1));
    final b = await ThemeBackgrounds.addBytes('mine', png(2));
    return BuiltInThemes.nord.copyWith(id: 'mine', name: 'Mine', backgrounds: [a, b], activeBackground: 1);
  }

  test('a theme with pictures goes out in one file and comes back as a new theme', () async {
    final theme = await themeWithPictures();
    final text = await ThemePackFile.write(theme);
    expect(ThemePackFile.isPack(text), isTrue);
    final back = await ThemePackFile.read(text, ThemeImporter());
    expect(back.id, isNot('mine'));
    expect(back.name, 'Mine');
    expect(back.style, theme.style);
    expect(back.backgrounds, hasLength(2));
    expect(back.activeBackground, 1);
    for (final (i, name) in back.backgrounds.indexed) {
      final file = await ThemeBackgrounds.fileFor(back.id, name);
      expect(await file!.readAsBytes(), png(i + 1), reason: 'pictures keep their order and content');
    }
  });

  test('a damaged picture is left out; the rest still come in', () async {
    final theme = await themeWithPictures();
    final json = jsonDecode(await ThemePackFile.write(theme)) as Map<String, dynamic>;
    ((json['pictures'] as List).first as Map)['data'] = base64Encode(utf8.encode('this is no picture'));
    final back = await ThemePackFile.read(jsonEncode(json), ThemeImporter());
    expect(back.backgrounds, hasLength(1));
    expect(back.activeBackground, lessThan(back.slideCount));
  });

  test('plain theme text is not a pack; packs from a newer app are refused', () async {
    expect(ThemePackFile.isPack(jsonEncode(BuiltInThemes.nord.toJson())), isFalse);
    final newer = jsonEncode({'format': ThemePackFile.format, 'version': 99, 'theme': BuiltInThemes.nord.toJson(), 'pictures': []});
    await expectLater(ThemePackFile.read(newer, ThemeImporter()), throwsA(isA<ThemeImportException>()));
  });
}
