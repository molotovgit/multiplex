import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A bundled font and where its licence text is.
class FontLicense {
  const FontLicense(this.packageName, this.asset);

  /// The name shown in the licence list.
  final String packageName;

  /// The OFL.txt that ships next to the font files.
  final String asset;
}

/// Adds the licences Flutter cannot find by itself (our bundled fonts) to
/// the "Open-source licences" page. Call [register] once at start-up.
abstract final class AppLicenses {
  static const fonts = [
    FontLicense('JetBrains Mono Nerd Font', 'assets/fonts/jetbrains-mono-nerd/OFL.txt'),
    FontLicense('IBM Plex Mono', 'assets/fonts/ibm-plex-mono/OFL.txt'),
  ];

  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    LicenseRegistry.addLicense(_fontLicenses);
  }

  /// Read lazily: the files are only loaded when the licence page opens.
  static Stream<LicenseEntry> _fontLicenses() async* {
    for (final font in fonts) {
      try {
        final text = await rootBundle.loadString(font.asset);
        yield LicenseEntryWithLineBreaks([font.packageName], text);
      } catch (e) {
        // A missing asset must not break the whole licence page.
        debugPrint('VaultTerm: could not load the licence for ${font.packageName} (${font.asset}): $e');
      }
    }
  }
}
