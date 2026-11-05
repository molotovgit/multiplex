import 'package:flutter_test/flutter_test.dart';
import 'package:vaultterm/app/theme.dart';
import 'package:vaultterm/app/theme_spec.dart';
import 'package:vaultterm/data/vault_backend.dart';
import 'package:vaultterm/data/vault_store.dart';

void main() {
  test('every built-in theme has 16 colours and a unique id', () {
    final ids = <String>{};
    for (final theme in BuiltInThemes.all) {
      expect(theme.ansi, hasLength(16), reason: theme.name);
      expect(ids.add(theme.id), isTrue, reason: 'duplicate id ${theme.id}');
    }
  });

  test('screen colours follow the theme: dark and light alike', () {
    final dark = AppColors.derive(BuiltInThemes.tokyoNight);
    expect(dark.isDark, isTrue);
    expect(dark.background.toARGB32(), BuiltInThemes.tokyoNight.background);
    expect(dark.accent.toARGB32(), BuiltInThemes.tokyoNight.accent);
    expect(dark.surface.computeLuminance(), greaterThan(dark.background.computeLuminance()));

    final light = AppColors.derive(BuiltInThemes.catppuccinLatte);
    expect(light.isDark, isFalse);
    expect(light.text.computeLuminance(), lessThan(light.background.computeLuminance()));
  });

  test('a custom theme round-trips through JSON and is used when chosen', () async {
    final store = await VaultStore.open(MemoryBackend());
    final mine = BuiltInThemes.nord.copyWith(id: 'mine', name: 'My Nord', accent: 0xFFFF0000);
    store.saveTheme(ThemeSpec.fromJson(mine.toJson()));
    store.updateSettings(store.settings.copyWith(themeId: 'mine'));
    expect(store.activeTheme.name, 'My Nord');
    expect(store.activeTheme.accent, 0xFFFF0000);

    // Deleting the theme in use falls back to the default.
    store.deleteTheme('mine');
    expect(store.activeTheme.id, BuiltInThemes.defaultId);
  });
}
