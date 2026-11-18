import '../../data/models.dart';
import '../../data/vault_store.dart';

/// Which screen of the remote machine the desktop shows.
enum DesktopScreenMode {
  mirror('Your monitor', 'Shows the screen you see at the desk, as gliff does; pinch to zoom in'),
  fitted('Phone-sized screen', 'Adds an extra screen to the desktop, sized for the phone, while connected');

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

/// How many pixels the picture has.
enum DesktopResolution {
  auto('Automatic', 'Your monitor at its full resolution (or this phone\'s size for a phone-sized screen)'),
  p1080('1080p', 'Up to 1920 × 1080'),
  p720('720p', 'Up to 1280 × 720: less data, softer text'),
  phone('Phone screen', 'As many pixels as this phone shows: the least data');

  const DesktopResolution(this.label, this.description);

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
    this.screen = DesktopScreenMode.mirror,
    this.touch = DesktopTouchMode.trackpad,
    this.quality = DesktopQuality.auto,
    this.resolution = DesktopResolution.auto,
    this.output = '',
    this.textSize = 1.0,
    this.showStats = false,
    this.haptics = true,
    this.syncClipboard = true,
    this.warmRadio = true,
    this.directVideo = true,
    this.autoKeyboard = true,
    this.builtInKeyboard = true,
  });

  final DesktopScreenMode screen;
  final DesktopTouchMode touch;
  final DesktopQuality quality;
  final DesktopResolution resolution;

  /// The monitor to mirror, by name (for example DP-1); empty means the
  /// one in focus.
  final String output;

  /// Size of things on a fitted screen, relative to the phone's own
  /// (1.0 = as large as the phone's apps).
  final double textSize;

  /// Frame rate and delay in a corner.
  final bool showStats;
  final bool haptics;

  /// Text copied on the desktop lands on the phone's clipboard.
  final bool syncClipboard;

  /// A tiny ping every 15 ms keeps the phone's radio from dozing off
  /// between pictures (it otherwise wakes 10-40 ms late on mobile data).
  final bool warmRadio;

  /// The decoder draws into a video layer of its own that Android shows
  /// directly, instead of a Flutter texture: about one refresh less delay.
  final bool directVideo;

  /// Show the keyboard by itself when a text field on the remote gets the
  /// focus, and hide it when it loses it.
  final bool autoKeyboard;

  /// Multiplex's own keyboard (with Ctrl, Alt, arrows and more) instead of
  /// the phone's.
  final bool builtInKeyboard;

  static const textSizes = [0.75, 0.85, 1.0, 1.15, 1.3];

  static DesktopSettings of(VaultStore store) => DesktopSettings.fromJson(store.settings.desktop);

  void saveTo(VaultStore store) => store.updateSettings(store.settings.copyWith(desktop: toJson()));

  DesktopSettings copyWith({
    DesktopScreenMode? screen,
    DesktopTouchMode? touch,
    DesktopQuality? quality,
    DesktopResolution? resolution,
    String? output,
    double? textSize,
    bool? showStats,
    bool? haptics,
    bool? syncClipboard,
    bool? warmRadio,
    bool? directVideo,
    bool? autoKeyboard,
    bool? builtInKeyboard,
  }) => DesktopSettings(
    screen: screen ?? this.screen,
    touch: touch ?? this.touch,
    quality: quality ?? this.quality,
    resolution: resolution ?? this.resolution,
    output: output ?? this.output,
    textSize: textSize ?? this.textSize,
    showStats: showStats ?? this.showStats,
    haptics: haptics ?? this.haptics,
    syncClipboard: syncClipboard ?? this.syncClipboard,
    warmRadio: warmRadio ?? this.warmRadio,
    directVideo: directVideo ?? this.directVideo,
    autoKeyboard: autoKeyboard ?? this.autoKeyboard,
    builtInKeyboard: builtInKeyboard ?? this.builtInKeyboard,
  );

  Map<String, dynamic> toJson() => {
    'screen': screen.name,
    'touch': touch.name,
    'quality': quality.name,
    'resolution': resolution.name,
    'output': output,
    'textSize': textSize,
    'showStats': showStats,
    'haptics': haptics,
    'syncClipboard': syncClipboard,
    'warmRadio': warmRadio,
    'directVideo': directVideo,
    'autoKeyboard': autoKeyboard,
    'builtInKeyboard': builtInKeyboard,
  };

  /// Unknown or missing values fall back to the defaults.
  factory DesktopSettings.fromJson(Map<String, dynamic> j) {
    const d = DesktopSettings();
    final size = j['textSize'];
    return DesktopSettings(
      screen: DesktopScreenMode.values.asNameMap()[j['screen']] ?? d.screen,
      touch: DesktopTouchMode.values.asNameMap()[j['touch']] ?? d.touch,
      quality: DesktopQuality.values.asNameMap()[j['quality']] ?? d.quality,
      resolution: DesktopResolution.values.asNameMap()[j['resolution']] ?? d.resolution,
      output: Json.str(j, 'output'),
      textSize: size is num ? size.toDouble().clamp(0.5, 2.0) : d.textSize,
      showStats: Json.boolean(j, 'showStats', d.showStats),
      haptics: Json.boolean(j, 'haptics', d.haptics),
      syncClipboard: Json.boolean(j, 'syncClipboard', d.syncClipboard),
      warmRadio: Json.boolean(j, 'warmRadio', d.warmRadio),
      directVideo: Json.boolean(j, 'directVideo', d.directVideo),
      autoKeyboard: Json.boolean(j, 'autoKeyboard', d.autoKeyboard),
      builtInKeyboard: Json.boolean(j, 'builtInKeyboard', d.builtInKeyboard),
    );
  }
}
