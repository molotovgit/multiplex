import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A PDF opened by Android's own PDF renderer, through a small native
/// channel (see PdfChannel.kt). Pages come back as pictures.
class PdfDocument {
  PdfDocument._(this._id, this.pageSizes, this._channel);

  static const channel = MethodChannel('multiplex/pdf');

  /// Only Android has the renderer this uses.
  static bool get supported => debugSupported ?? (!kIsWeb && Platform.isAndroid);

  /// Lets tests pretend to be on Android (the channel is mocked there).
  @visibleForTesting
  static bool? debugSupported;

  final int _id;
  final MethodChannel _channel;
  bool _closed = false;

  /// Each page's size in PDF points, so pages can be laid out before
  /// they are drawn.
  final List<Size> pageSizes;

  int get pageCount => pageSizes.length;

  static Future<PdfDocument> open(String path, {MethodChannel channel = channel}) async {
    final answer = await channel.invokeMapMethod<String, Object?>('open', {'path': path});
    if (answer == null) throw const FormatException('The PDF could not be opened.');
    final id = answer['id'] as int;
    final raw = (answer['sizes'] as List).cast<num>();
    final sizes = [for (var i = 0; i + 1 < raw.length; i += 2) Size(raw[i].toDouble(), raw[i + 1].toDouble())];
    return PdfDocument._(id, sizes, channel);
  }

  /// Draws page [index] (from 0) [width] pixels wide, as PNG bytes.
  Future<Uint8List> render(int index, int width) async {
    if (_closed) throw StateError('The PDF is closed.');
    final bytes = await _channel.invokeMethod<Uint8List>('render', {'id': _id, 'page': index, 'width': width});
    if (bytes == null) throw const FormatException('The page could not be drawn.');
    return bytes;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.invokeMethod<void>('close', {'id': _id});
    } on PlatformException {
      // Already gone on the native side.
    } on MissingPluginException {
      // No renderer on this platform: nothing was opened there.
    }
  }
}
