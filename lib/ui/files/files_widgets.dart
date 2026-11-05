import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/terminal_fonts.dart';
import '../../app/theme.dart';

/// Layout numbers shared by the file screens.
abstract final class FilesLayout {
  /// Content never gets wider than this on big screens.
  static const maxWidth = 840.0;

  /// Room under the list so the floating button never covers the last row.
  static const listBottomPadding = 88.0;
}

/// Animation timing. Motion only marks a change (the transfer bar
/// appearing); it is switched off when the system asks for less motion.
abstract final class FilesMotion {
  static const _short = Duration(milliseconds: 200);

  static Duration short(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : _short;
}

/// The terminal font as a text style, for text fields that show paths or
/// file contents (MonoText covers read-only text).
abstract final class MonoStyle {
  static TextStyle? of(BuildContext context, [TextStyle? base]) {
    final settings = AppScope.store(context).settings;
    final family = TerminalFonts.byId(settings, settings.terminalFontId).family;
    return (base ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(fontFamily: family, letterSpacing: 0);
  }
}

/// Keeps content at a readable width on wide screens.
class FilesWidth extends StatelessWidget {
  const FilesWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: FilesLayout.maxWidth),
      child: child,
    ),
  );
}

/// A strip across the top that says the connection is gone.
class ConnectionLostBanner extends StatelessWidget {
  const ConnectionLostBanner({super.key, this.message = 'The connection to this server closed. Reconnect from Sessions to work with files again.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: colors.danger.withValues(alpha: 0.14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.link_off, color: colors.danger),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.text))),
          ],
        ),
      ),
    );
  }
}

/// A calm notice strip, for example "this file opens read-only".
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Container(
      width: double.infinity,
      color: colors.raised,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: colors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.text))),
        ],
      ),
    );
  }
}

/// A spinner with a line saying what is happening.
class BusyMessage extends StatelessWidget {
  const BusyMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Messages that need more than the shared Toast offers.
abstract final class FileToasts {
  /// A short message with one button, for example "Undo".
  static void withAction(BuildContext context, String message, {required String label, required VoidCallback onPressed}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: label, onPressed: onPressed),
        ),
      );
  }

  /// "Saved to ..." with a button that copies the path.
  static void saved(BuildContext context, String localPath) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Saved to $localPath'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Copy path',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: localPath));
              messenger.showSnackBar(const SnackBar(content: Text('Path copied')));
            },
          ),
        ),
      );
  }
}
