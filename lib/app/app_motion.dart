import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import 'app_scope.dart';

/// How long theme changes and sheets take, from the motion setting. When
/// the system asks for less motion, everything is instant.
class AppMotion {
  const AppMotion(this.speed);

  /// The setting, already turned off when the system asks for less motion.
  final MotionSpeed speed;

  /// The motion for [setting], given whether the system asks for less.
  factory AppMotion.resolve(MotionSpeed setting, {required bool reduceMotion}) =>
      AppMotion(reduceMotion ? MotionSpeed.off : setting);

  /// The motion for this screen: the saved setting and the system's wish.
  /// Outside the app's scope (some tests) the normal speed is used.
  static AppMotion of(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return AppMotion.resolve(scope?.notifier?.settings.motion ?? MotionSpeed.normal, reduceMotion: reduce);
  }

  /// Whether the system asks for less motion, read before MaterialApp
  /// has made its MediaQuery.
  static bool get systemReducesMotion =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  /// Cross-fade between the old and the new theme.
  Duration get theme => switch (speed) {
        MotionSpeed.off => Duration.zero,
        MotionSpeed.fast => const Duration(milliseconds: 120),
        MotionSpeed.normal => const Duration(milliseconds: 250),
      };

  /// Sheets slide in at this speed and leave a little faster.
  AnimationStyle get sheet => switch (speed) {
        MotionSpeed.off => AnimationStyle.noAnimation,
        MotionSpeed.fast => const AnimationStyle(duration: Duration(milliseconds: 150), reverseDuration: Duration(milliseconds: 100)),
        MotionSpeed.normal => const AnimationStyle(duration: Duration(milliseconds: 250), reverseDuration: Duration(milliseconds: 200)),
      };
}
