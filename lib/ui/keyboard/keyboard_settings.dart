import '../../data/models.dart';
import '../../data/vault_store.dart';

/// Which letter arrangement the keyboard uses.
enum KeyboardLayoutKind {
  qwerty('QWERTY', 'English and most other languages'),
  qwertz('QWERTZ', 'German and Central European'),
  azerty('AZERTY', 'French and Belgian');

  const KeyboardLayoutKind(this.label, this.description);

  final String label;
  final String description;
}

/// How tall the keys are.
enum KeyHeightOption {
  compact('Compact'),
  normal('Normal'),
  large('Large');

  const KeyHeightOption(this.label);

  final String label;
}

/// The corners of the keys.
enum KeyShape {
  rounded('Rounded'),
  square('Square');

  const KeyShape(this.label);

  final String label;
}

/// Everything the user can change about the built-in keyboard. Stored as
/// plain JSON in [AppSettings.keyboard], so new options never need a
/// change to the app's settings class.
class KeyboardSettings {
  const KeyboardSettings({
    this.enabled = true,
    this.layout = KeyboardLayoutKind.qwerty,
    this.keyHeight = KeyHeightOption.normal,
    this.shape = KeyShape.rounded,
    this.boldLabels = false,
    this.showAlternates = true,
    this.swipeForSymbols = true,
    this.keyPreview = true,
    this.haptics = true,
    this.sound = false,
    this.showRecentCommands = true,
  });

  /// True: the built-in keyboard replaces the phone's keyboard in terminals.
  final bool enabled;
  final KeyboardLayoutKind layout;
  final KeyHeightOption keyHeight;
  final KeyShape shape;
  final bool boldLabels;

  /// Shows the swipe-up character small in the corner of each key.
  final bool showAlternates;

  /// Swiping up on a key types its alternate character.
  final bool swipeForSymbols;

  /// Shows a bubble with the character above the finger.
  final bool keyPreview;
  final bool haptics;
  final bool sound;

  /// A row of recent commands for this host above the keys.
  final bool showRecentCommands;

  /// Reads the saved keyboard settings.
  static KeyboardSettings of(VaultStore store) => KeyboardSettings.fromJson(store.settings.keyboard);

  /// Saves these settings.
  void saveTo(VaultStore store) => store.updateSettings(store.settings.copyWith(keyboard: toJson()));

  KeyboardSettings copyWith({
    bool? enabled,
    KeyboardLayoutKind? layout,
    KeyHeightOption? keyHeight,
    KeyShape? shape,
    bool? boldLabels,
    bool? showAlternates,
    bool? swipeForSymbols,
    bool? keyPreview,
    bool? haptics,
    bool? sound,
    bool? showRecentCommands,
  }) =>
      KeyboardSettings(
        enabled: enabled ?? this.enabled,
        layout: layout ?? this.layout,
        keyHeight: keyHeight ?? this.keyHeight,
        shape: shape ?? this.shape,
        boldLabels: boldLabels ?? this.boldLabels,
        showAlternates: showAlternates ?? this.showAlternates,
        swipeForSymbols: swipeForSymbols ?? this.swipeForSymbols,
        keyPreview: keyPreview ?? this.keyPreview,
        haptics: haptics ?? this.haptics,
        sound: sound ?? this.sound,
        showRecentCommands: showRecentCommands ?? this.showRecentCommands,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'layout': layout.name,
        'keyHeight': keyHeight.name,
        'shape': shape.name,
        'boldLabels': boldLabels,
        'showAlternates': showAlternates,
        'swipeForSymbols': swipeForSymbols,
        'keyPreview': keyPreview,
        'haptics': haptics,
        'sound': sound,
        'showRecentCommands': showRecentCommands,
      };

  /// Unknown or missing values fall back to the defaults, so a backup
  /// from another version still loads.
  factory KeyboardSettings.fromJson(Map<String, dynamic> j) {
    const d = KeyboardSettings();
    return KeyboardSettings(
      enabled: Json.boolean(j, 'enabled', d.enabled),
      layout: KeyboardLayoutKind.values.asNameMap()[j['layout']] ?? d.layout,
      keyHeight: KeyHeightOption.values.asNameMap()[j['keyHeight']] ?? d.keyHeight,
      shape: KeyShape.values.asNameMap()[j['shape']] ?? d.shape,
      boldLabels: Json.boolean(j, 'boldLabels', d.boldLabels),
      showAlternates: Json.boolean(j, 'showAlternates', d.showAlternates),
      swipeForSymbols: Json.boolean(j, 'swipeForSymbols', d.swipeForSymbols),
      keyPreview: Json.boolean(j, 'keyPreview', d.keyPreview),
      haptics: Json.boolean(j, 'haptics', d.haptics),
      sound: Json.boolean(j, 'sound', d.sound),
      showRecentCommands: Json.boolean(j, 'showRecentCommands', d.showRecentCommands),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeyboardSettings &&
      other.enabled == enabled &&
      other.layout == layout &&
      other.keyHeight == keyHeight &&
      other.shape == shape &&
      other.boldLabels == boldLabels &&
      other.showAlternates == showAlternates &&
      other.swipeForSymbols == swipeForSymbols &&
      other.keyPreview == keyPreview &&
      other.haptics == haptics &&
      other.sound == sound &&
      other.showRecentCommands == showRecentCommands;

  @override
  int get hashCode =>
      Object.hash(enabled, layout, keyHeight, shape, boldLabels, showAlternates, swipeForSymbols, keyPreview, haptics, sound, showRecentCommands);
}
