import 'package:flutter/services.dart';

/// A notification the phone showed.
class PhoneNotification {
  const PhoneNotification({required this.app, required this.title, required this.text});

  /// The app's name as the phone shows it ("Messages").
  final String app;
  final String title;
  final String text;

  static PhoneNotification? parse(Object? raw) {
    if (raw is! Map) return null;
    final app = raw['app'], title = raw['title'], text = raw['text'];
    if (app is! String || title is! String || text is! String) return null;
    if (title.trim().isEmpty && text.trim().isEmpty) return null;
    return PhoneNotification(app: app, title: title, text: text);
  }
}

/// What a link to a computer needs from the phone itself, which only
/// Android can give: ringing out loud, the battery, the notifications.
class PhoneBridge {
  const PhoneBridge({this.channel = const MethodChannel('multiplex/phone'), this.notices = const EventChannel('multiplex/phone/notifications')});

  final MethodChannel channel;
  final EventChannel notices;

  /// Rings out loud (also when the phone is silent) for at most [seconds],
  /// with a notification that stops it.
  Future<void> ring(int seconds) => _quiet(() => channel.invokeMethod<void>('ring', {'seconds': seconds}));

  Future<void> stopRinging() => _quiet(() => channel.invokeMethod<void>('stopRing'));

  /// The battery level (0 to 100) and whether it is charging; null where
  /// that cannot be told.
  Future<({int level, bool charging})?> battery() async {
    try {
      final raw = await channel.invokeMethod<Map<Object?, Object?>>('battery');
      final level = raw?['level'], charging = raw?['charging'];
      return level is int && charging is bool && level >= 0 ? (level: level.clamp(0, 100), charging: charging) : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The phone's notifications as they are posted. Empty until the user
  /// has given Multiplex notification access in Android's settings.
  Stream<PhoneNotification> notifications() =>
      notices.receiveBroadcastStream().map(PhoneNotification.parse).where((n) => n != null).cast<PhoneNotification>().handleError((Object _) {});

  /// Whether Android lets Multiplex see notifications.
  Future<bool> notificationAccess() async {
    try {
      return await channel.invokeMethod<bool>('notificationAccess') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Android's page where that access is given.
  Future<void> openNotificationAccess() => _quiet(() => channel.invokeMethod<void>('openNotificationAccess'));

  static Future<void> _quiet(Future<void> Function() call) async {
    try {
      await call();
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // Nothing here is worth an error to the user.
    }
  }
}
