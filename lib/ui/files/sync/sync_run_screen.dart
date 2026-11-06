import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../data/sync_pairs.dart';
import '../../../src/rust/api/sftp.dart';
import '../../../src/rust/api/sftp_types.dart';
import '../../../src/rust/api/transfer_types.dart';
import '../../common/widgets.dart';
import '../file_format.dart';
import '../two_pane/phone_storage.dart';
import 'sync_backend.dart';

enum _Stage { comparing, preview, syncing, done, failed }

/// "Sync now": compares the two folders, shows every step before
/// anything changes, then runs them with progress and a summary.
class SyncRunScreen extends StatefulWidget {
  const SyncRunScreen({super.key, required this.pair, required this.backend, this.newTransfer});

  final SyncPair pair;
  final Future<SyncBackend> Function() backend;
  final FileTransfer Function()? newTransfer;

  @override
  State<SyncRunScreen> createState() => _SyncRunScreenState();
}

class _SyncRunScreenState extends State<SyncRunScreen> {
  _Stage _stage = _Stage.comparing;
  List<SyncAction> _plan = const [];
  SyncReport? _report;
  String? _error;
  FileTransfer? _transfer;
  StreamSubscription<TransferProgress>? _progress;
  BigInt _done = BigInt.zero;
  BigInt _total = BigInt.zero;
  SyncBackend? _backend;

  List<SyncAction> get _steps => _plan.where((a) => a.kind != SyncActionKind.conflict).toList();

  @override
  void initState() {
    super.initState();
    _compare();
  }

  @override
  void dispose() {
    _transfer?.cancel();
    _progress?.cancel();
    super.dispose();
  }

  FileTransfer _newTransfer() {
    final transfer = _transfer = (widget.newTransfer ?? FileTransfer.create)();
    _progress?.cancel();
    _progress = transfer.watch().listen((p) {
      if (mounted) {
        setState(() {
          _done = p.transferred;
          _total = p.total;
        });
      }
    }, onError: (Object _) {});
    return transfer;
  }

  Future<void> _compare() async {
    setState(() {
      _stage = _Stage.comparing;
      _error = null;
    });
    try {
      final backend = _backend ??= await widget.backend();
      final plan = await backend.plan(widget.pair, _newTransfer());
      if (mounted) {
        setState(() {
          _plan = plan;
          _stage = _Stage.preview;
        });
      }
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _sync() async {
    final steps = _steps;
    final deletes = steps.where(SyncWords.isDelete).length;
    if (deletes > 0) {
      final sure = await Confirm.ask(
        context,
        title: 'Delete $deletes ${deletes == 1 ? 'item' : 'items'}?',
        message: 'Mirror is on, so what is not in the source folder is deleted, folders with everything inside. This cannot be undone.',
        action: 'Sync and delete',
      );
      if (!sure || !mounted) return;
    }
    setState(() {
      _stage = _Stage.syncing;
      _done = BigInt.zero;
      _total = BigInt.zero;
    });
    try {
      final report = await _backend!.apply(widget.pair, steps, _newTransfer());
      if (!mounted) return;
      AppScope.store(context).saveSyncPair(widget.pair.copyWith(lastSyncedAt: DateTime.now()));
      setState(() {
        _report = report;
        _stage = _Stage.done;
      });
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _error = FileErrors.message(error);
      _stage = _Stage.failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sync ${widget.pair.name}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(top: false, child: _body(context)),
      bottomNavigationBar: _bottom(context),
    );
  }

  Widget _body(BuildContext context) => switch (_stage) {
    _Stage.comparing => const _Busy('Comparing the two folders. Nothing changes yet.'),
    _Stage.syncing => _Busy('Syncing: ${FileSizes.progress(_done, _total)}', fraction: _total > BigInt.zero ? (_done / _total).clamp(0.0, 1.0) : null),
    _Stage.failed => EmptyState(
      icon: Icons.sync_problem_outlined,
      title: 'The sync stopped',
      message: '${_error ?? ''} If the phone folder is outside the app\'s own files, Android may need "All files access" for Multiplex.',
      actionLabel: 'Try again',
      onAction: _compare,
    ),
    _Stage.done => _Summary(report: _report!),
    _Stage.preview when _plan.isEmpty => const EmptyState(
      icon: Icons.check_circle_outline,
      title: 'Already in step',
      message: 'Both folders have the same files, by size and change time.',
    ),
    _Stage.preview => _PlanList(plan: _plan),
  };

  Widget? _bottom(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final Widget button;
    switch (_stage) {
      case _Stage.preview when _steps.isNotEmpty:
        button = FilledButton.icon(onPressed: _sync, icon: const Icon(Icons.sync), label: Text('Sync ${_steps.length} ${_steps.length == 1 ? 'change' : 'changes'}'));
      case _Stage.syncing:
        button = OutlinedButton(
          onPressed: () => _transfer?.cancel(),
          child: const Text('Stop'),
        );
      case _Stage.failed when PhoneStorage.supportsAccess:
        button = OutlinedButton(onPressed: PhoneStorage.askAllFilesAccess, child: const Text('Allow access to phone files'));
      default:
        return null;
    }
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(width: double.infinity, height: 48, child: button),
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.message, {this.fraction});

  final String message;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: fraction, semanticsLabel: message),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The steps, grouped by what happens, before anything runs.
class _PlanList extends StatelessWidget {
  const _PlanList({required this.plan});

  final List<SyncAction> plan;

  static const _order = [SyncActionKind.copyToRight, SyncActionKind.copyToLeft, SyncActionKind.deleteOnRight, SyncActionKind.deleteOnLeft, SyncActionKind.conflict];

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final bytes = plan.fold(BigInt.zero, (sum, a) => sum + a.size);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'This is what the sync will do. Nothing has changed yet.${bytes > BigInt.zero ? ' ${FileSizes.human(bytes)} to copy.' : ''}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
        ),
        for (final kind in _order)
          if (plan.any((a) => a.kind == kind)) ...[
            SectionHeader('${SyncWords.kind(kind)} (${plan.where((a) => a.kind == kind).length})'),
            for (final step in plan.where((a) => a.kind == kind)) _StepRow(step: step),
          ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final SyncAction step;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final (icon, color) = switch (step.kind) {
      SyncActionKind.copyToRight => (Icons.upload_outlined, colors.accent),
      SyncActionKind.copyToLeft => (Icons.download_outlined, colors.accent),
      SyncActionKind.deleteOnRight || SyncActionKind.deleteOnLeft => (Icons.delete_outline, colors.danger),
      SyncActionKind.conflict => (Icons.help_outline, colors.muted),
    };
    final size = step.size > BigInt.zero ? ' · ${FileSizes.human(step.size)}' : '';
    return ListTile(
      leading: Icon(icon, color: color, semanticLabel: SyncWords.kind(step.kind)),
      title: MonoText(step.isDir ? '${step.path}/' : step.path, maxLines: 2),
      subtitle: Text('${SyncWords.reason(step.reason)}$size'),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.report});

  final SyncReport report;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final failed = report.failed;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(failed.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_outlined, size: 40, color: failed.isEmpty ? colors.live : colors.danger),
        const SizedBox(height: 16),
        Text(
          failed.isEmpty ? 'Folders are in step' : 'Synced, with ${failed.length} ${failed.length == 1 ? 'problem' : 'problems'}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text('Copied ${report.copied}, deleted ${report.deleted}.', textAlign: TextAlign.center, style: TextStyle(color: colors.muted)),
        for (final problem in failed) ...[const SizedBox(height: 8), MonoText(problem, maxLines: 4, style: TextStyle(color: colors.danger))],
      ],
    );
  }
}
