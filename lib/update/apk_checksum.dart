import 'dart:io';

import 'package:crypto/crypto.dart';

import 'update_errors.dart';

/// The SHA-256 published next to each APK, and the check of a download
/// against it.
abstract final class ApkChecksum {
  static final _hex = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Reads a `.sha256` file: the hex digest, optionally followed by the
  /// file name (as `sha256sum` writes it). Returns it in lower case.
  static String parse(String text) {
    final first = text.trim().split(RegExp(r'\s+')).first;
    if (!_hex.hasMatch(first)) throw const UpdateException('The checksum file of the release is not a SHA-256. The update was not installed.');
    return first.toLowerCase();
  }

  /// The SHA-256 of [file] in lower-case hex.
  static Future<String> of(File file) async => (await sha256.bind(file.openRead()).first).toString();

  /// Whether [file] has exactly the digest [expectedHex].
  static Future<bool> matches(File file, String expectedHex) async => await of(file) == expectedHex.toLowerCase();
}
