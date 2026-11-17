import 'package:flutter/services.dart';

/// What only Android can do for reading text: take the picture of a page
/// (with Google's page scanner), and make any picture ready to send.
class TextScanner {
  const TextScanner({this.channel = const MethodChannel('multiplex/textscan')});

  final MethodChannel channel;

  /// Opens the page scanner. The picture as a JPEG; null when the user
  /// backed out. Throws a sentence when the scanner cannot be used here.
  Future<Uint8List?> scan() async {
    try {
      return await channel.invokeMethod<Uint8List>('scan');
    } on MissingPluginException {
      throw Exception('Scanning needs an Android phone with Google Play services.');
    } on PlatformException catch (e) {
      throw Exception('The page scanner could not be opened${e.message == null ? '.' : ': ${e.message}'}');
    }
  }

  /// A picture file as a JPEG of a size that keeps text sharp; null when
  /// it is not a picture.
  Future<Uint8List?> shrink(String path) async {
    try {
      return await channel.invokeMethod<Uint8List>('shrink', path);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
