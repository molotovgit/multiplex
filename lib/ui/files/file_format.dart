import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

import '../../src/rust/api/sftp_types.dart';

/// File sizes in units people read easily: "512 B", "4.2 KB", "38 MB".
abstract final class FileSizes {
  static const _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  static final _step = BigInt.from(1024);

  static String human(BigInt bytes) {
    if (bytes < _step) return '$bytes B';
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < _units.length - 1) {
      value /= 1024;
      unit++;
    }
    // One decimal for small numbers ("4.2 KB"), none for big ones ("420 KB").
    var text = value.toStringAsFixed(value < 10 ? 1 : 0);
    // Rounding can land on 1024 ("1024 KB"); show the next unit instead.
    if (double.parse(text) >= 1024 && unit < _units.length - 1) {
      unit++;
      text = (value / 1024).toStringAsFixed(1);
    }
    return '$text ${_units[unit]}';
  }

  /// "1.2 MB of 4.0 MB", or just the amount when the total is unknown.
  static String progress(BigInt done, BigInt total) => total > BigInt.zero ? '${human(done)} of ${human(total)}' : human(done);
}

/// Unix permission bits, shown the way `ls -l` does: "drwxr-xr-x".
abstract final class FileModes {
  /// The nine read/write/execute bits, owner first.
  static const bits = [0x100, 0x080, 0x040, 0x020, 0x010, 0x008, 0x004, 0x002, 0x001];
  static const _letters = 'rwxrwxrwx';
  static const _setUser = 0x800;
  static const _setGroup = 0x400;
  static const _sticky = 0x200;

  /// All bits a permission change can touch (0o7777).
  static const mask = 0xFFF;

  static String describe(int mode, EntryKind kind) {
    final type = switch (kind) {
      EntryKind.directory => 'd',
      EntryKind.symlink => 'l',
      EntryKind.file => '-',
      EntryKind.other => '?',
    };
    final chars = [for (var i = 0; i < 9; i++) mode & bits[i] != 0 ? _letters[i] : '-'];
    // Special bits replace the execute letter, as in `ls`.
    chars[2] = _special(mode, _setUser, chars[2], 's');
    chars[5] = _special(mode, _setGroup, chars[5], 's');
    chars[8] = _special(mode, _sticky, chars[8], 't');
    return '$type${chars.join()}';
  }

  static String _special(int mode, int bit, String current, String letter) {
    if (mode & bit == 0) return current;
    return current == '-' ? letter.toUpperCase() : letter;
  }

  /// "755", or "4755" when a special bit is set.
  static String octal(int mode) {
    final masked = mode & mask;
    final text = masked.toRadixString(8);
    return masked > 0x1FF ? text.padLeft(4, '0') : text.padLeft(3, '0');
  }

  /// Reads "644" or "0755"; null when the text is not 3 or 4 octal digits.
  static int? parseOctal(String text) {
    final trimmed = text.trim();
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(trimmed)) return null;
    return int.parse(trimmed, radix: 8);
  }
}

/// Short, local dates for the file list: "Today 14:05", "5 Nov 09:30",
/// "5 Nov 2024".
abstract final class FileDates {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String short(int? secondsSinceEpoch, {DateTime? now}) {
    if (secondsSinceEpoch == null) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000);
    final today = now ?? DateTime.now();
    final clock = '${_two(time.hour)}:${_two(time.minute)}';
    if (time.year == today.year && time.month == today.month && time.day == today.day) return 'Today $clock';
    final day = '${time.day} ${_months[time.month - 1]}';
    return time.year == today.year ? '$day $clock' : '$day ${time.year}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Turns errors into one plain sentence, plus what to do about the
/// common ones.
abstract final class FileErrors {
  /// Advice for messages the SFTP server sends often, matched in lower case.
  static const _hints = {
    'permission denied': 'Your account on the server is not allowed to do this.',
    'no such file': 'It may have been moved or deleted. Refresh the folder and try again.',
    'connection lost': 'Reconnect to the server and try again.',
    'no connection': 'Reconnect to the server and try again.',
    'no space': 'Free up some space and try again.',
    // The SFTP catch-all; OpenSSH sends it for "already exists" and
    // "folder not empty", among others.
    'failure': 'The server refused without giving a reason. Check that the name is free, then try again.',
  };

  static String message(Object error) {
    var text = switch (error) {
      AnyhowException(:final message) => message,
      FileSystemException(:final message, :final osError) => osError == null ? message : '$message (${osError.message})',
      StateError(:final message) => message,
      _ => error.toString(),
    };
    // Rust adds "Caused by:" chains and sometimes a backtrace; the first
    // line says what went wrong.
    text = text.trim().split('\n').first.trim();
    if (text.startsWith('Exception: ')) text = text.substring('Exception: '.length);
    // SFTP errors come as "<code>: <server message>", which often repeat
    // each other ("Permission denied: Permission denied").
    final colon = text.indexOf(': ');
    if (colon > 0 && text.substring(0, colon).toLowerCase() == text.substring(colon + 2).toLowerCase()) text = text.substring(0, colon);
    if (text.isEmpty) return 'Something went wrong.';
    text = text[0].toUpperCase() + text.substring(1);
    if (!text.endsWith('.')) text = '$text.';
    final lower = text.toLowerCase();
    final hint = _hints.entries.where((h) => lower.contains(h.key)).firstOrNull?.value;
    return hint == null ? text : '$text $hint';
  }
}
