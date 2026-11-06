import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../common/widgets.dart';
import 'link_detector.dart';

/// Opens a web address in the phone's browser. Tests swap it for a fake.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// The small sheet a tap on a link opens: open it, copy it, or (for a
/// path) show it in the file browser.
class LinkSheet extends StatelessWidget {
  const LinkSheet({super.key, required this.link, this.onOpenPath, this.openUrl = defaultOpener});

  final DetectedLink link;

  /// Shows a path in the file browser; null where there is none.
  final ValueChanged<String>? onOpenPath;
  final UrlOpener openUrl;

  static Future<bool> defaultOpener(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<void> show(BuildContext context, DetectedLink link, {ValueChanged<String>? onOpenPath, UrlOpener openUrl = defaultOpener}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => LinkSheet(link: link, onOpenPath: onOpenPath, openUrl: openUrl),
    );
  }

  Future<void> _open(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.tryParse(link.text);
    var opened = false;
    if (uri != null) {
      try {
        opened = await openUrl(uri);
      } on PlatformException {
        opened = false;
      }
    }
    navigator.pop();
    if (!opened) messenger?.showSnackBar(const SnackBar(content: Text('No app could open this link')));
  }

  Future<void> _copy(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: link.text));
    navigator.pop();
    messenger?.showSnackBar(const SnackBar(content: Text('Copied')));
  }

  void _openPath(BuildContext context) {
    Navigator.of(context).pop();
    onOpenPath?.call(link.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final what = switch (link.kind) {
      LinkKind.url => 'Link',
      LinkKind.address => 'Address',
      LinkKind.path => 'Path',
    };
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(what, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.muted)),
                const SizedBox(height: 4),
                MonoText(link.text, maxLines: 3),
              ],
            ),
          ),
          if (link.kind == LinkKind.url)
            ListTile(leading: const Icon(Icons.open_in_browser), title: const Text('Open in browser'), onTap: () => _open(context)),
          if (link.kind == LinkKind.path && onOpenPath != null)
            ListTile(leading: const Icon(Icons.folder_open), title: const Text('Open in Files'), onTap: () => _openPath(context)),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Copy'), onTap: () => _copy(context)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
