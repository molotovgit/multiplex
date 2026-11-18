import 'package:flutter/services.dart';

/// The phone as keyboard and mouse of another device. The reports are
/// made on the computer (the Rust core checks them); this only passes
/// them on to whatever carries them: Bluetooth on the phone as it is.
/// Tests pass a stand-in.
abstract class PhoneHands {
  /// Sends keyboard reports (8 bytes each) and mouse reports (3 bytes
  /// each), in that order. Null when sent; otherwise why not, in words
  /// for whoever asked.
  Future<String?> send(Uint8List keys, Uint8List pointer);

  /// A picture from the camera, as a file on the phone; null when there
  /// is none to be had, with [problem] saying why.
  Future<({String? path, String? problem})> look();
}

/// Android's own (see `HandsChannel.kt`).
class AndroidPhoneHands implements PhoneHands {
  const AndroidPhoneHands([this._channel = const MethodChannel('multiplex/hands')]);

  final MethodChannel _channel;

  static const notConnected = 'The phone is not connected to a device as its keyboard. Open Hands on the phone and connect one.';

  @override
  Future<String?> send(Uint8List keys, Uint8List pointer) async {
    try {
      return await _channel.invokeMethod<String>('send', {'keys': keys, 'pointer': pointer});
    } on MissingPluginException {
      return 'This phone cannot be a keyboard for another device.';
    } on PlatformException catch (e) {
      return e.message ?? notConnected;
    }
  }

  @override
  Future<({String? path, String? problem})> look() async => (path: null, problem: 'Looking through the camera is not built yet.');
}
