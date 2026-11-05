import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme_backgrounds.dart';
import '../../app/theme_spec.dart';
import '../../app/theme_slides.dart';
import '../../app/theme_style.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import 'theme_editor_screen.dart';
import 'theme_export.dart';
import 'theme_text_editor_screen.dart';

/// Everything the user can do with a theme: use it, edit it, copy it,
/// export it, cycle its backgrounds and delete it. Every change is saved
/// at once.
class ThemeActions {
  ThemeActions(this.context);

  final BuildContext context;

  VaultStore get _store => AppScope.store(context);

  /// Makes [theme] the app's theme and says so. The screens restyle at
  /// once; open terminals are repainted in the new colours.
  void use(ThemeSpec theme) {
    _apply(theme);
    Toast.show(context, '${theme.name} applied');
  }

  /// Makes [theme] the app's theme without a message, for the quick
  /// switcher where the change itself is the feedback.
  void useQuietly(ThemeSpec theme) => _apply(theme);

  /// Saves a theme the user made or changed. With [andUse] it also
  /// becomes the app's theme.
  void save(ThemeSpec theme, {required bool andUse}) {
    _store.saveTheme(theme);
    if (andUse || _store.settings.themeId == theme.id) {
      _apply(theme);
    }
  }

  /// Changes the look of the theme in use, saved at once. A built-in theme
  /// never changes, so the first change saves a copy and uses that.
  void updateStyle(ThemeStyle style) {
    final active = _store.activeTheme;
    if (active.style == style) return;
    if (active.builtIn) {
      // Built-in themes have no pictures, so there is nothing to copy.
      final copy = copyOf(active).copyWith(style: style);
      save(copy, andUse: true);
      Toast.show(context, 'Saved a copy: ${copy.name}. Built-in themes stay as they are.');
    } else {
      save(active.copyWith(style: style), andUse: false);
    }
  }

  /// Moves the theme in use on to its next background, the way Omarchy
  /// cycles wallpapers: its drawn backdrops, then its pictures, then the
  /// plain colour. Says so when the theme has none.
  void nextBackground() {
    final active = _store.activeTheme;
    final settings = _store.settings;
    final count = active.slideCount;
    if (count == 0) {
      Toast.show(context, '${active.name} has no backgrounds. Add pictures in the theme editor, or install a theme that has them.');
      return;
    }
    final next = (ActiveSlide.index(active, settings) + 1) % count;
    if (active.builtIn) {
      // Built-in themes never change, so the choice is kept in the settings.
      _store.updateSettings(settings.copyWith(backdropPicks: {...settings.backdropPicks, active.id: next}));
    } else {
      save(active.copyWith(activeBackground: next), andUse: false);
    }
    final slide = active.slideAt(next);
    Toast.show(context, slide == null ? 'Plain background' : 'Background ${next + 1} of ${count - 1}: ${BackgroundNames.of(slide)}');
  }

  void _apply(ThemeSpec theme) {
    _store.updateSettings(_store.settings.copyWith(themeId: theme.id));
    AppScope.sessions(context).applyTerminalTheme();
  }

  /// Opens the editor on a copy of the theme in use.
  Future<void> create() async => _openEditor(await copyWithPictures(_store.activeTheme), isNew: true, title: 'New theme');

  /// Opens the editor. A built-in theme cannot change, so its editor
  /// works on a copy instead.
  Future<void> edit(ThemeSpec theme) =>
      theme.builtIn ? editCopy(theme) : _openEditor(theme, isNew: false, title: 'Edit theme');

  Future<void> editCopy(ThemeSpec theme) async => _openEditor(await copyWithPictures(theme), isNew: true, title: 'New theme');

  /// Opens the whole theme as text. A built-in theme is opened as a copy.
  Future<void> editAsText(ThemeSpec theme) async {
    final isNew = theme.builtIn;
    final target = isNew ? await copyWithPictures(theme) : theme;
    final pictures = await ThemeBackgrounds.list(target.id);
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ThemeTextEditorScreen(theme: target, isNew: isNew, pictures: pictures.toSet())),
    );
  }

  /// Opens the editor on a theme that was just imported, so the user can
  /// look it over before keeping it.
  Future<void> review(ThemeSpec imported) => _openEditor(imported, isNew: true, title: 'Review imported theme');

  /// Saves a copy straight away, next to the original.
  Future<void> duplicate(ThemeSpec theme) async {
    final copy = await copyWithPictures(theme);
    _store.saveTheme(copy);
    if (context.mounted) Toast.show(context, 'Saved a copy: ${copy.name}');
  }

  Future<void> export(ThemeSpec theme) => ThemeExportDialog.show(context, theme);

  Future<void> delete(ThemeSpec theme) async {
    final inUse = _store.settings.themeId == theme.id;
    final ok = await Confirm.ask(
      context,
      title: 'Delete theme?',
      message: inUse
          ? '"${theme.name}" is in use. It will be deleted and the default theme will be used instead.'
          : '"${theme.name}" will be deleted, with its background pictures. This cannot be undone.',
      action: 'Delete theme',
    );
    if (!ok || !context.mounted) return;
    _store.deleteTheme(theme.id);
    if (inUse) AppScope.sessions(context).applyTerminalTheme();
    await ThemeBackgrounds.deleteFolder(theme.id);
    if (context.mounted) Toast.show(context, 'Deleted ${theme.name}');
  }

  /// A new custom theme with the same colours, a new id and "copy" added
  /// to the name. Its pictures are not copied; see [copyWithPictures].
  static ThemeSpec copyOf(ThemeSpec theme) => theme.copyWith(id: VaultStore.newId(), name: '${theme.name} copy');

  /// A copy of [theme] with its background pictures copied into the new
  /// theme's own folder.
  static Future<ThemeSpec> copyWithPictures(ThemeSpec theme) async {
    final copy = copyOf(theme);
    await ThemeBackgrounds.copy(theme.id, copy.id, theme.backgrounds);
    return copy;
  }

  Future<void> _openEditor(ThemeSpec theme, {required bool isNew, required String title}) async {
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ThemeEditorScreen(theme: theme, isNew: isNew, title: title)),
    );
  }
}
