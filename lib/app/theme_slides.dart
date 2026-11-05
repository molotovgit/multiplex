import '../data/app_settings.dart';
import 'theme_spec.dart';

/// Which background step a theme shows. Built-in themes cannot be saved,
/// so their step is kept in the settings; the user's own themes keep it
/// themselves.
abstract final class ActiveSlide {
  static int index(ThemeSpec theme, AppSettings settings) =>
      theme.builtIn ? (settings.backdropPicks[theme.id] ?? theme.activeBackground) : theme.activeBackground;

  /// The backdrop or picture to show, or null for the plain colour.
  static ThemeSlide? of(ThemeSpec theme, AppSettings settings) => theme.slideAt(index(theme, settings));
}

/// Words for a background step, shown to the user.
abstract final class BackgroundNames {
  static String of(ThemeSlide? slide) => switch (slide) {
        null => 'Plain colour',
        PatternSlide(:final pattern) => pattern.label,
        PictureSlide() => 'Your picture',
      };
}
