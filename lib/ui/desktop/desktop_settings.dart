import '../../data/models.dart';
import '../../data/vault_store.dart';

/// Which screen of the remote machine the desktop shows.
enum DesktopScreenMode {
  fitted('Fitted to this phone', 'A private screen sized for the phone; text stays readable and it turns with the phone'),
  mirror('Mirror the monitor', 'Shows the monitor you would see at the desk, scaled down to fit');

  const DesktopScreenMode(this.label, this.description);

  final String label;
  final String description;
}

/// How a finger moves the remote pointer.
enum DesktopTouchMode {
  trackpad('Trackpad', 'Drag anywhere to move the pointer, tap to click. Precise, like a laptop trackpad'),
  direct('Direct touch', 'Tap exactly where you want to click');

  const DesktopTouchMode(this.label, this.description);

  final String label;
  final String description;
}

/// How much picture the stream carries.
enum DesktopQuality {
  auto('Automatic', 'Full detail, adjusted to the network as it changes'),
  saver('Data saver', 'A smaller stream for slow or metered networks');

  const DesktopQuality(this.label, this.description);

  final String label;
  final String description;
}

/// Everything the user can change about the remote desktop. Stored as
/// plain JSON in [AppSettings.desktop].
class DesktopSettings {
  const DesktopSettings({
    this.screen = DesktopScreenMode.fitted,
    this.touch = DesktopTouchMode.trackpad,
    this.quality = DesktopQuality.auto,
    this.textSize = 1.0,
    this.showStats = false,
    this.haptics = true,
    this.syncClipboard = true,
  });

  final DesktopScreenMode screen;
  final DesktopTouchMode touch;
  final DesktopQuality quality;

  /// Size of things on a fitted screen, relative to the phone's own
  /// (1.0 = as large as the phone's apps).
  final double textSize;

  /// Frame rate and delay in a corner.
  final bool showStats;
  final bool haptics;

  /// Text copied on the desktop lands on the phone's clipboard.
  final bool syncClipboard;

  static const textSizes = [0.75, 0.85, 1.0, 1.15, 1.3];

  static DesktopSettings of(VaultStore store) => DesktopSettings.fromJson(store.settings.desktop);

  void saveTo(VaultStore store) => store.updateSettings(store.settings.copyWith(desktop: toJson()));

  DesktopSettings copyWith({
    DesktopScreenMode? screen,
    DesktopTouchMode? touch,
    DesktopQuality? quality,
    double? textSize,
    bool? showStats,
    bool? haptics,
    bool? syncClipboard,
  }) => DesktopSettings(
    screen: screen ?? this.screen,
    touch: touch ?? this.touch,
    quality: quality ?? this.quality,
    textSize: textSize ?? this.textSize,
    showStats: showStats ?? this.showStats,
    haptics: haptics ?? this.haptics,
    syncClipboard: syncClipboard ?? this.syncClipboard,
  );

  Map<String, dynamic> toJson() => {
    'screen': screen.name,
    'touch': touch.name,
    'quality': quality.name,
    'textSize': textSize,
    'showStats': showStats,
    'haptics': haptics,
    'syncClipboard': syncClipboard,
  };

  /// Unknown or missing values fall back to the defaults.
  factory DesktopSettings.fromJson(Map<String, dynamic> j) {
    const d = DesktopSettings();
    final size = j['textSize'];
    return DesktopSettings(
      screen: DesktopScreenMode.values.asNameMap()[j['screen']] ?? d.screen,
      touch: DesktopTouchMode.values.asNameMap()[j['touch']] ?? d.touch,
      quality: DesktopQuality.values.asNameMap()[j['quality']] ?? d.quality,
      textSize: size is num ? size.toDouble().clamp(0.5, 2.0) : d.textSize,
      showStats: Json.boolean(j, 'showStats', d.showStats),
      haptics: Json.boolean(j, 'haptics', d.haptics),
      syncClipboard: Json.boolean(j, 'syncClipboard', d.syncClipboard),
    );
  }
}
