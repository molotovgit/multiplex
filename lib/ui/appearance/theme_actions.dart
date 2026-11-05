import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme_spec.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import 'theme_editor_screen.dart';
import 'theme_export.dart';

/// Everything the user can do with a theme: use it, edit it, copy it,
/// export it and delete it. Every change is saved at once.
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

  /// Saves a theme the user made or changed. With [andUse] it also
  /// becomes the app's theme.
  void save(ThemeSpec theme, {required bool andUse}) {
    _store.saveTheme(theme);
    if (andUse || _store.settings.themeId == theme.id) {
      _apply(theme);
    }
  }

  void _apply(ThemeSpec theme) {
    _store.updateSettings(_store.settings.copyWith(themeId: theme.id));
    AppScope.sessions(context).applyTerminalTheme();
  }

  /// Opens the editor on a copy of the theme in use.
  Future<void> create() => _openEditor(copyOf(_store.activeTheme), isNew: true, title: 'New theme');

  /// Opens the editor. A built-in theme cannot change, so its editor
  /// works on a copy instead.
  Future<void> edit(ThemeSpec theme) =>
      theme.builtIn ? editCopy(theme) : _openEditor(theme, isNew: false, title: 'Edit theme');

  Future<void> editCopy(ThemeSpec theme) => _openEditor(copyOf(theme), isNew: true, title: 'New theme');

  /// Opens the editor on a theme that was just imported, so the user can
  /// look it over before keeping it.
  Future<void> review(ThemeSpec imported) => _openEditor(imported, isNew: true, title: 'Review imported theme');

  /// Saves a copy straight away, next to the original.
  void duplicate(ThemeSpec theme) {
    final copy = copyOf(theme);
    _store.saveTheme(copy);
    Toast.show(context, 'Saved a copy: ${copy.name}');
  }

  Future<void> export(ThemeSpec theme) => ThemeExportDialog.show(context, theme);

  Future<void> delete(ThemeSpec theme) async {
    final inUse = _store.settings.themeId == theme.id;
    final ok = await Confirm.ask(
      context,
      title: 'Delete theme?',
      message: inUse
          ? '"${theme.name}" is in use. It will be deleted and the default theme will be used instead.'
          : '"${theme.name}" will be deleted. This cannot be undone.',
      action: 'Delete theme',
    );
    if (!ok || !context.mounted) return;
    _store.deleteTheme(theme.id);
    if (inUse) AppScope.sessions(context).applyTerminalTheme();
    Toast.show(context, 'Deleted ${theme.name}');
  }

  /// A new custom theme with the same colours, a new id and "copy" added
  /// to the name.
  static ThemeSpec copyOf(ThemeSpec theme) => theme.copyWith(id: VaultStore.newId(), name: '${theme.name} copy');

  Future<void> _openEditor(ThemeSpec theme, {required bool isNew, required String title}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ThemeEditorScreen(theme: theme, isNew: isNew, title: title)),
      );
}
