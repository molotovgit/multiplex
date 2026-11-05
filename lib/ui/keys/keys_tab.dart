import '../../app/app_icons.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import 'key_detail_screen.dart';
import 'key_labels.dart';
import 'key_tools.dart';
import 'page_width.dart';

/// The saved keys, sorted by name. Tapping one opens its details.
class KeysTab extends StatelessWidget {
  const KeysTab({super.key, required this.tools, required this.onNewKey});

  final KeyTools tools;
  final VoidCallback onNewKey;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final keys = [...store.keys]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (keys.isEmpty) {
          return EmptyState(
            icon: Icons.key_outlined,
            title: 'No keys yet',
            message: 'A key lets you log in to servers without typing a password. Generate a new one, or import a key you already use.',
            actionLabel: 'New key',
            onAction: onNewKey,
          );
        }
        return PageWidth(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: PageLayout.fabClearance),
            itemCount: keys.length,
            itemBuilder: (context, i) => KeyTile(key: ValueKey(keys[i].id), storedKey: keys[i], tools: tools),
          ),
        );
      },
    );
  }
}

/// One key: name (with a lock when it has a passphrase), type and
/// fingerprint.
class KeyTile extends StatelessWidget {
  const KeyTile({super.key, required this.storedKey, required this.tools});

  final StoredKey storedKey;
  final KeyTools tools;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return ListTile(
      isThreeLine: true,
      leading: const AppIcon(AppIcons.vpnKey),
      title: Row(
        children: [
          Flexible(child: Text(storedKey.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (storedKey.encrypted)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'Protected by a passphrase',
                child: Icon(Icons.lock_outline, size: 16, color: colors.muted, semanticLabel: 'Protected by a passphrase'),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(KeyAlgorithms.label(storedKey.algorithm)),
          MonoText(storedKey.fingerprint, maxLines: 1, style: text.bodySmall?.copyWith(color: colors.muted)),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => KeyDetailScreen(keyId: storedKey.id, tools: tools),
        ),
      ),
    );
  }
}
