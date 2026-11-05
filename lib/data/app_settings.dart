import 'models.dart';

/// How the terminal cursor looks when the program does not choose.
enum CursorStyle { block, bar, underline }

/// A font the user added from a file. The file itself is kept in the
/// app's folder; this records its name.
class CustomFont {
  const CustomFont({required this.id, required this.name, required this.fileName});

  final String id;
  final String name;
  final String fileName;

  /// Family name the font is registered under while the app runs.
  String get family => 'custom-$id';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'fileName': fileName};

  factory CustomFont.fromJson(Map<String, dynamic> j) =>
      CustomFont(id: Json.str(j, 'id'), name: Json.str(j, 'name'), fileName: Json.str(j, 'fileName'));
}

/// User preferences. Saved inside the vault with everything else.
class AppSettings {
  const AppSettings({
    this.themeId = 'ember',
    this.terminalFontId = 'jetbrains',
    this.fontSize = 14,
    this.lineHeight = 1.2,
    this.cursorStyle = CursorStyle.block,
    this.cursorBlink = true,
    this.keyBar = defaultKeyBar,
    this.customFonts = const [],
    this.scrollbackLines = 5000,
    this.keepAliveSecs = 30,
    this.boldIsBright = false,
    this.appLock = false,
    this.keepScreenOn = true,
  });

  /// One theme styles the whole app: screens and terminal.
  final String themeId;

  /// One of the bundled fonts, "system", or a [CustomFont] id.
  final String terminalFontId;

  /// Terminal font size in logical pixels.
  final double fontSize;

  /// Row height as a multiple of the font size.
  final double lineHeight;
  final CursorStyle cursorStyle;
  final bool cursorBlink;

  /// Ids of the keys in the bar above the keyboard, in order.
  final List<String> keyBar;
  final List<CustomFont> customFonts;
  final int scrollbackLines;

  /// Send a keep-alive after this many quiet seconds (0 = off).
  final int keepAliveSecs;
  final bool boldIsBright;

  /// Ask for fingerprint, face or device PIN when the app opens.
  final bool appLock;
  final bool keepScreenOn;

  static const minFontSize = 8.0;
  static const maxFontSize = 28.0;
  static const minLineHeight = 1.0;
  static const maxLineHeight = 1.6;

  static const defaultKeyBar = [
    'esc', 'tab', 'ctrl', 'alt', 'left', 'down', 'up', 'right', //
    'pipe', 'slash', 'dash', 'tilde', 'home', 'end', 'pgup', 'pgdn', 'paste', 'snippets',
  ];

  AppSettings copyWith({
    String? themeId,
    String? terminalFontId,
    double? fontSize,
    double? lineHeight,
    CursorStyle? cursorStyle,
    bool? cursorBlink,
    List<String>? keyBar,
    List<CustomFont>? customFonts,
    int? scrollbackLines,
    int? keepAliveSecs,
    bool? boldIsBright,
    bool? appLock,
    bool? keepScreenOn,
  }) =>
      AppSettings(
        themeId: themeId ?? this.themeId,
        terminalFontId: terminalFontId ?? this.terminalFontId,
        fontSize: (fontSize ?? this.fontSize).clamp(minFontSize, maxFontSize),
        lineHeight: (lineHeight ?? this.lineHeight).clamp(minLineHeight, maxLineHeight),
        cursorStyle: cursorStyle ?? this.cursorStyle,
        cursorBlink: cursorBlink ?? this.cursorBlink,
        keyBar: keyBar ?? this.keyBar,
        customFonts: customFonts ?? this.customFonts,
        scrollbackLines: scrollbackLines ?? this.scrollbackLines,
        keepAliveSecs: keepAliveSecs ?? this.keepAliveSecs,
        boldIsBright: boldIsBright ?? this.boldIsBright,
        appLock: appLock ?? this.appLock,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      );

  Map<String, dynamic> toJson() => {
        'themeId': themeId,
        'terminalFontId': terminalFontId,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'cursorStyle': cursorStyle.name,
        'cursorBlink': cursorBlink,
        'keyBar': keyBar,
        'customFonts': customFonts.map((f) => f.toJson()).toList(),
        'scrollbackLines': scrollbackLines,
        'keepAliveSecs': keepAliveSecs,
        'boldIsBright': boldIsBright,
        'appLock': appLock,
        'keepScreenOn': keepScreenOn,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    double number(String key, double fallback) => j[key] is num ? (j[key] as num).toDouble() : fallback;
    return AppSettings(
      themeId: Json.str(j, 'themeId', 'ember'),
      terminalFontId: Json.str(j, 'terminalFontId', 'jetbrains'),
      fontSize: number('fontSize', 14).clamp(minFontSize, maxFontSize),
      lineHeight: number('lineHeight', 1.2).clamp(minLineHeight, maxLineHeight),
      cursorStyle: CursorStyle.values.asNameMap()[j['cursorStyle']] ?? CursorStyle.block,
      cursorBlink: Json.boolean(j, 'cursorBlink', true),
      keyBar: j['keyBar'] is List ? (j['keyBar'] as List).whereType<String>().toList() : defaultKeyBar,
      customFonts: Json.list(j, 'customFonts').map(CustomFont.fromJson).toList(),
      scrollbackLines: Json.integer(j, 'scrollbackLines', 5000),
      keepAliveSecs: Json.integer(j, 'keepAliveSecs', 30),
      boldIsBright: Json.boolean(j, 'boldIsBright', false),
      appLock: Json.boolean(j, 'appLock', false),
      keepScreenOn: Json.boolean(j, 'keepScreenOn', true),
    );
  }
}
