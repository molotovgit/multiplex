/// Decides whether pasted text needs a second look before it reaches the
/// shell.
///
/// Every line break in a paste presses Enter, so several lines run at
/// once, and a single line can still do damage the user did not read:
/// text copied from a web page may hide a `sudo` or `rm -rf`. Such pastes
/// are shown first; everything else goes straight through.
abstract final class PasteGuard {
  /// Commands that change or wipe a system. Matched anywhere in the text.
  static const risky = ['sudo ', 'rm -rf', 'mkfs', 'dd if=', '> /dev/sd', 'chmod -R 777'];

  /// Why the text should be confirmed, in words for the dialog. Empty
  /// when it can be pasted straight away.
  static List<String> reasons(String text) => [
        ?_linesReason(text),
        for (final word in risky)
          if (text.contains(word)) 'It contains "${word.trim()}".',
      ];

  static bool needsConfirm(String text) => reasons(text).isNotEmpty;

  static String? _linesReason(String text) {
    if (!text.contains('\n') && !text.contains('\r')) return null;
    final lines = text.split(RegExp(r'\r\n|\r|\n')).where((l) => l.trim().isNotEmpty).length;
    if (lines > 1) return 'It has $lines lines. Each one runs as soon as it is pasted.';
    return 'It ends with a line break, so it runs as soon as it is pasted.';
  }
}
