import 'package:flutter/services.dart';

/// A picture from a clipboard: its kind (`png`, `jpeg`, `webp` or `gif`)
/// and its bytes.
class ClipboardPicture {
  const ClipboardPicture(this.kind, this.bytes);

  final String kind;
  final Uint8List bytes;
}

/// Pictures on this phone's clipboard (Android's part; text goes through
/// Flutter's own clipboard calls).
abstract final class PhoneClipboardPictures {
  static const _channel = MethodChannel('multiplex/clipboard');

  /// The picture on the phone's clipboard, if it holds one. Android only
  /// shows the clipboard to the app in front.
  static Future<ClipboardPicture?> read() async {
    try {
      final picture = await _channel.invokeMapMethod<String, Object?>('read');
      final kind = picture?['kind'], bytes = picture?['bytes'];
      return kind is String && bytes is Uint8List ? ClipboardPicture(kind, bytes) : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Puts text on the phone's clipboard without going through the app's
  /// screen: for when a paired computer's clipboard arrives while the app
  /// has none (swiped away, or started with the phone).
  static Future<bool> writeText(String text) async {
    try {
      return await _channel.invokeMethod<bool>('writeText', text) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> write(ClipboardPicture picture) async {
    try {
      await _channel.invokeMethod<bool>('write', {'kind': picture.kind, 'bytes': picture.bytes});
    } on MissingPluginException {
      // No picture clipboard on this platform.
    } on PlatformException {
      // A clipboard is never worth an error.
    }
  }
}
