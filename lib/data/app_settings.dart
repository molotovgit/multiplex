import 'package:flutter/material.dart';

import 'models.dart';

/// User preferences. Saved inside the vault with everything else.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.terminalThemeId = 'ember',
    this.fontSize = 14,
    this.scrollbackLines = 5000,
    this.keepAliveSecs = 30,
    this.boldIsBright = false,
    this.appLock = false,
    this.keepScreenOn = true,
  });

  final ThemeMode themeMode;
  final String terminalThemeId;

  /// Terminal font size in logical pixels.
  final double fontSize;
  final int scrollbackLines;

  /// Send a keep-alive after this many quiet seconds (0 = off).
  final int keepAliveSecs;
  final bool boldIsBright;

  /// Ask for fingerprint, face or device PIN when the app opens.
  final bool appLock;
  final bool keepScreenOn;

  static const minFontSize = 8.0;
  static const maxFontSize = 28.0;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? terminalThemeId,
    double? fontSize,
    int? scrollbackLines,
    int? keepAliveSecs,
    bool? boldIsBright,
    bool? appLock,
    bool? keepScreenOn,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        terminalThemeId: terminalThemeId ?? this.terminalThemeId,
        fontSize: (fontSize ?? this.fontSize).clamp(minFontSize, maxFontSize),
        scrollbackLines: scrollbackLines ?? this.scrollbackLines,
        keepAliveSecs: keepAliveSecs ?? this.keepAliveSecs,
        boldIsBright: boldIsBright ?? this.boldIsBright,
        appLock: appLock ?? this.appLock,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'terminalThemeId': terminalThemeId,
        'fontSize': fontSize,
        'scrollbackLines': scrollbackLines,
        'keepAliveSecs': keepAliveSecs,
        'boldIsBright': boldIsBright,
        'appLock': appLock,
        'keepScreenOn': keepScreenOn,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values.asNameMap()[j['themeMode']] ?? ThemeMode.dark,
        terminalThemeId: Json.str(j, 'terminalThemeId', 'ember'),
        fontSize: (j['fontSize'] is num ? (j['fontSize'] as num).toDouble() : 14.0).clamp(minFontSize, maxFontSize),
        scrollbackLines: Json.integer(j, 'scrollbackLines', 5000),
        keepAliveSecs: Json.integer(j, 'keepAliveSecs', 30),
        boldIsBright: Json.boolean(j, 'boldIsBright', false),
        appLock: Json.boolean(j, 'appLock', false),
        keepScreenOn: Json.boolean(j, 'keepScreenOn', true),
      );
}
