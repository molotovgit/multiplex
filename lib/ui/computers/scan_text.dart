import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_motion.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../platform/text_scanner.dart';
import '../../sessions/error_text.dart';
import '../../sessions/session_manager.dart';
import '../common/widgets.dart';
import '../hosts/host_connector.dart';
import '../settings/settings_widgets.dart';

/// What a computer read in a picture.
class TextReading {
  const TextReading(this.text, this.languages);

  /// Empty: none could be read.
  final String text;

  /// The languages the computer reads (its reader's names, such as `eng`).
  final List<String> languages;
}

/// Has the computer read a picture's text and put it on its clipboard.
/// The real one is a command in the Rust core; tests pass a stand-in.
typedef ReadPicture = Future<TextReading> Function(Uint8List picture);

/// Text on paper to the computer's clipboard: the phone photographs it,
/// the computer reads it.
abstract final class ScanText {
  static Future<ReadPicture?> _reader(BuildContext context, Host host) async {
    final LiveSession? session = await HostConnector.connect(context, host);
    if (session == null) return null;
    return (picture) async {
      final found = await session.ssh.shareReadText(picture: picture);
      return TextReading(found.text, found.languages);
    };
  }

  /// Photographs a page with the phone's scanner and has [host] read it.
  static Future<void> fromCamera(BuildContext context, Host host, {TextScanner scanner = const TextScanner()}) async {
    final read = await _reader(context, host);
    if (read == null || !context.mounted) return;
    final Uint8List? picture;
    try {
      picture = await scanner.scan();
    } catch (e) {
      if (context.mounted) Toast.show(context, errorSentence(e, fallback: 'The page scanner could not be opened.'));
      return;
    }
    if (picture == null || !context.mounted) return;
    await TextReadSheet.show(context, host: host, picture: picture, read: read);
  }

  /// Has [host] read a picture that is already a file (one shared to the app).
  static Future<void> fromPicture(BuildContext context, Host host, String path, {TextScanner scanner = const TextScanner()}) async {
    final read = await _reader(context, host);
    if (read == null || !context.mounted) return;
    final picture = await scanner.shrink(path);
    if (!context.mounted) return;
    if (picture == null) {
      Toast.show(context, 'That is not a picture this phone can open.');
      return;
    }
    await TextReadSheet.show(context, host: host, picture: picture, read: read);
  }

  /// Whether a shared file is a picture by its name.
  static bool isPicture(String name) {
    final lower = name.toLowerCase();
    return const ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.bmp'].any(lower.endsWith);
  }
}

/// Shows the reading as it happens, then the text: it is on the
/// computer's clipboard, and can be copied on the phone too.
class TextReadSheet extends StatefulWidget {
  const TextReadSheet({super.key, required this.host, required this.picture, required this.read});

  final Host host;
  final Uint8List picture;
  final ReadPicture read;

  static Future<void> show(BuildContext context, {required Host host, required Uint8List picture, required ReadPicture read}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      builder: (_) => TextReadSheet(host: host, picture: picture, read: read),
    );
  }

  @override
  State<TextReadSheet> createState() => _TextReadSheetState();
}

class _TextReadSheetState extends State<TextReadSheet> {
  TextReading? _reading;
  String? _problem;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final reading = await widget.read(widget.picture);
      if (mounted) setState(() => _reading = reading);
    } catch (e) {
      if (mounted) setState(() => _problem = errorSentence(e, fallback: '${widget.host.title} could not read the picture.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reading = _reading;
    final computer = widget.host.title;
    final Widget body;
    if (_problem != null) {
      body = NoticeBox(tone: NoticeTone.error, text: _problem!);
    } else if (reading == null) {
      body = Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: Text('$computer is reading the picture…', style: text.bodyLarge)),
          ],
        ),
      );
    } else if (reading.text.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No text could be read in the picture', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(
            '$computer reads: ${reading.languages.join(', ')}. Text in another language needs that language installed for its reader (tesseract) there. A closer, sharper picture also helps.',
            style: text.bodyMedium?.copyWith(color: colors.muted),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: colors.live),
                const SizedBox(width: 8),
                Expanded(child: Text('On $computer\'s clipboard', style: text.titleMedium)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
            child: SingleChildScrollView(child: SelectableText(reading.text, style: text.bodyMedium)),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: reading.text));
                if (context.mounted) Toast.show(context, 'Copied on this phone too');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy here too'),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 24),
      child: AnimatedSize(duration: const Duration(milliseconds: 200), alignment: Alignment.topCenter, child: body),
    );
  }
}
