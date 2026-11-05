import 'package:flutter/material.dart';

import '../../app/app_icons.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../src/rust/api/ssh_types.dart';
import '../common/widgets.dart';
import 'key_labels.dart';
import 'page_width.dart';
import 'undo_toast.dart';

/// Servers whose identity the user has accepted, sorted by address.
class KnownHostsTab extends StatelessWidget {
  const KnownHostsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final known = [...store.knownHosts]..sort((a, b) => a.endpoint.compareTo(b.endpoint));
        if (known.isEmpty) {
          return const EmptyState(
            icon: Icons.verified_user_outlined,
            title: 'No trusted servers yet',
            message:
                'The first time you connect to a server, Multiplex shows its fingerprint and asks you to trust it. '
                'Servers you trust are listed here.',
          );
        }
        return PageWidth(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            itemCount: known.length,
            itemBuilder: (context, i) => KnownHostTile(key: ValueKey('${known[i].endpoint} ${known[i].publicKey}'), known: known[i]),
          ),
        );
      },
    );
  }
}

/// One trusted server: address, key type, when it was added, fingerprint.
class KnownHostTile extends StatelessWidget {
  const KnownHostTile({super.key, required this.known});

  final KnownHost known;

  /// "host:port", with IPv6 addresses in brackets so the port stands out.
  String get address => known.host.contains(':') ? '[${known.host}]:${known.port}' : '${known.host}:${known.port}';

  Future<void> _forget(BuildContext context) async {
    final store = AppScope.store(context);
    final sure = await Confirm.ask(
      context,
      title: 'Forget $address?',
      message: 'The next connection to this server will show its fingerprint again and ask you to trust it.',
      action: 'Forget server',
    );
    if (!sure) return;
    store.forgetKnownHost(known);
    if (!context.mounted) return;
    // Undo trusts the same key again (dated today).
    UndoToast.show(context, 'Forgot $address', () {
      store.trustHostKey(known.host, known.port, HostKeyInfo(algorithm: known.algorithm, fingerprint: known.fingerprint, publicKey: known.publicKey));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final added = MaterialLocalizations.of(context).formatShortDate(known.addedAt);
    return ListTile(
      isThreeLine: true,
      leading: const AppIcon(AppIcons.verifiedUser),
      title: MonoText(address, maxLines: 1),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${KeyAlgorithms.label(known.algorithm)} · Added $added'),
          MonoText(known.fingerprint, maxLines: 1, style: text.bodySmall?.copyWith(color: colors.muted)),
        ],
      ),
      trailing: IconButton(tooltip: 'Forget server', icon: const Icon(Icons.delete_outline), onPressed: () => _forget(context)),
    );
  }
}
