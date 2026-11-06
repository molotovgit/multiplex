import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../data/sync_pairs.dart';
import '../../../sessions/session_manager.dart';
import '../../../src/rust/api/sftp.dart';
import '../../common/widgets.dart';
import '../file_format.dart';
import '../files_widgets.dart';
import '../two_pane/two_pane_screen.dart';
import 'sync_backend.dart';
import 'sync_pair_editor.dart';
import 'sync_run_screen.dart';

/// The folders kept in sync with one server: add, change, delete, and
/// "Sync now", which always shows the list of changes first.
class SyncPairsScreen extends StatelessWidget {
  const SyncPairsScreen({super.key, required this.session, this.serverPath = '', this.backend, this.newTransfer, this.pickFolder});

  final LiveSession session;

  /// The folder open in Files, offered for a new pair.
  final String serverPath;
  final Future<SyncBackend> Function()? backend;
  final FileTransfer Function()? newTransfer;
  final Future<String?> Function()? pickFolder;

  Future<SyncBackend> _backend() async => (backend ?? () async => CoreSyncBackend(await TwoPaneScreen.filesFor(session)))();

  Future<void> _edit(BuildContext context, [SyncPair? pair]) async {
    final store = AppScope.store(context);
    final saved = await SyncPairEditor.show(context, hostId: session.host.id, pair: pair, serverPath: serverPath, pickFolder: pickFolder);
    if (saved != null) store.saveSyncPair(saved);
  }

  Future<void> _delete(BuildContext context, SyncPair pair) async {
    final store = AppScope.store(context);
    final sure = await Confirm.ask(
      context,
      title: 'Delete "${pair.name}"?',
      message: 'Only the saved pair goes. The files in both folders stay as they are.',
      action: 'Delete pair',
    );
    if (sure) store.deleteSyncPair(pair.id);
  }

  void _run(BuildContext context, SyncPair pair) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SyncRunScreen(pair: pair, backend: _backend, newTransfer: newTransfer)));
  }

  @override
  Widget build(BuildContext context) {
    final pairs = AppScope.watch(context).syncPairsFor(session.host.id);
    return Scaffold(
      appBar: AppBar(title: Text('Folder sync with ${session.host.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        top: false,
        child: FilesWidth(
          child: pairs.isEmpty
              ? EmptyState(
                  icon: Icons.sync,
                  title: 'No folders kept in sync yet',
                  message: 'Pair a folder on this phone with one on ${session.host.title}. Each sync shows what will change before it changes it.',
                  actionLabel: 'New sync pair',
                  onAction: () => _edit(context),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: FilesLayout.listBottomPadding),
                  itemCount: pairs.length,
                  itemBuilder: (context, i) => _PairTile(
                    pair: pairs[i],
                    onSync: () => _run(context, pairs[i]),
                    onEdit: () => _edit(context, pairs[i]),
                    onDelete: () => _delete(context, pairs[i]),
                  ),
                ),
        ),
      ),
      floatingActionButton: pairs.isEmpty
          ? null
          : FloatingActionButton.extended(onPressed: () => _edit(context), icon: const Icon(Icons.add), label: const Text('New sync pair')),
    );
  }
}

class _PairTile extends StatelessWidget {
  const _PairTile({required this.pair, required this.onSync, required this.onEdit, required this.onDelete});

  final SyncPair pair;
  final VoidCallback onSync;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted);
    final arrow = switch (pair.way) {
      SyncWay.toServer => '→',
      SyncWay.toPhone => '←',
      SyncWay.both => '⇄',
    };
    final last = pair.lastSyncedAt;
    final when = last == null ? 'Never synced' : 'Last synced ${FileDates.short(last.millisecondsSinceEpoch ~/ 1000)}';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(pair.name, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Options for ${pair.name}',
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    PopupMenuItem(value: onEdit, child: const Text('Edit')),
                    PopupMenuItem(value: onDelete, child: Text('Delete', style: TextStyle(color: colors.danger))),
                  ],
                ),
              ],
            ),
            MonoText('${pair.phonePath}  $arrow  ${pair.serverPath}', maxLines: 3, style: small),
            const SizedBox(height: 4),
            Text('${pair.way.label}${pair.mirrors ? ', mirror' : ''} · $when', style: small),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(onPressed: onSync, icon: const Icon(Icons.sync), label: const Text('Sync now')),
          ],
        ),
      ),
    );
  }
}
