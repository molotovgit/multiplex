import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../sessions/session_manager.dart';
import '../../src/rust/api/sftp.dart';
import 'file_format.dart';

enum TransferDirection { upload, download }

enum TransferState { waiting, running, done, failed, cancelled }

/// The work behind one upload or download. The queue decides when it
/// runs; the task only knows how to copy its file.
abstract class TransferTask {
  /// The file name shown in the transfer list.
  String get name;

  TransferDirection get direction;

  /// The server folder the file goes to or comes from.
  String get remoteFolder;

  /// Two tasks with the same key never run at the same time. Null means
  /// the task can run next to anything.
  String? get exclusiveKey => null;

  /// Copies the file, reporting progress through [transfer]. Returns
  /// where the file ended up, to show the user.
  Future<String> run(FileTransfer transfer);

  /// Tidies up after the user cancelled, for example removes a half
  /// uploaded file. Must not throw.
  Future<void> afterCancel() async {}
}

/// One entry in the transfer list, with its live progress.
class TransferJob {
  TransferJob(this.task);

  final TransferTask task;

  TransferState _state = TransferState.waiting;
  BigInt _transferred = BigInt.zero;
  BigInt _total = BigInt.zero;
  String? _error;
  String? _result;
  FileTransfer? _transfer;
  bool _cancelRequested = false;

  String get name => task.name;
  TransferDirection get direction => task.direction;
  TransferState get state => _state;
  BigInt get transferred => _transferred;

  /// Size in bytes, zero while unknown.
  BigInt get total => _total;

  /// What went wrong, when the state is failed.
  String? get error => _error;

  /// Where the file ended up, when the state is done.
  String? get result => _result;

  bool get isActive => _state == TransferState.waiting || _state == TransferState.running;

  /// Share of the file copied so far (0 to 1), or null while unknown.
  double? get fraction {
    if (_state == TransferState.done) return 1;
    if (_total <= BigInt.zero) return null;
    return (_transferred / _total).clamp(0.0, 1.0);
  }
}

/// Runs uploads and downloads in the background, at most [maxRunning]
/// at a time, so the user can keep browsing while files copy.
class TransferQueue extends ChangeNotifier {
  TransferQueue({this.maxRunning = 2, FileTransfer Function()? newTransfer}) : _newTransfer = newTransfer ?? FileTransfer.create;

  /// One queue per connection, kept with the session object itself, so
  /// transfers carry on (and stay listed) when the user leaves the files
  /// screen and comes back.
  static final _bySession = Expando<TransferQueue>('transfers');

  static TransferQueue of(LiveSession session) => _bySession[session] ??= TransferQueue();

  final int maxRunning;
  final FileTransfer Function() _newTransfer;
  final List<TransferJob> _jobs = [];
  final _finished = StreamController<TransferJob>.broadcast();
  bool _disposed = false;

  List<TransferJob> get jobs => List.unmodifiable(_jobs);

  /// Fires once for every job that ends: done, failed or cancelled.
  Stream<TransferJob> get finished => _finished.stream;

  int get runningCount => _jobs.where((j) => j.state == TransferState.running).length;
  int get waitingCount => _jobs.where((j) => j.state == TransferState.waiting).length;
  int get activeCount => _jobs.where((j) => j.isActive).length;
  int countIn(TransferState state) => _jobs.where((j) => j.state == state).length;

  /// Progress of everything still active (0 to 1), or null while unknown.
  double? get overallFraction {
    final active = _jobs.where((j) => j.isActive).toList();
    if (active.isEmpty) return null;
    var done = BigInt.zero;
    var total = BigInt.zero;
    for (final job in active) {
      done += job.transferred;
      total += job.total;
    }
    if (total <= BigInt.zero) return null;
    return (done / total).clamp(0.0, 1.0);
  }

  TransferJob add(TransferTask task) {
    final job = TransferJob(task);
    _jobs.add(job);
    _startWaiting();
    notifyListeners();
    return job;
  }

  void cancel(TransferJob job) {
    if (job._state == TransferState.waiting) {
      job._state = TransferState.cancelled;
      _ended(job);
    } else if (job._state == TransferState.running) {
      job._cancelRequested = true;
      job._transfer?.cancel();
    }
  }

  void cancelAll() {
    for (final job in List.of(_jobs)) {
      cancel(job);
    }
  }

  /// Removes done, failed and cancelled jobs from the list.
  void clearFinished() {
    _jobs.removeWhere((j) => !j.isActive);
    notifyListeners();
  }

  /// Starts waiting jobs while there is room, in the order they came.
  void _startWaiting() {
    while (runningCount < maxRunning) {
      final busyKeys = {
        for (final j in _jobs)
          if (j.state == TransferState.running && j.task.exclusiveKey != null) j.task.exclusiveKey,
      };
      final next = _jobs
          .where((j) => j.state == TransferState.waiting && (j.task.exclusiveKey == null || !busyKeys.contains(j.task.exclusiveKey)))
          .firstOrNull;
      if (next == null) return;
      // Marks the job as running before the first await, so the loop
      // counts it straight away.
      unawaited(_run(next));
    }
  }

  Future<void> _run(TransferJob job) async {
    job._state = TransferState.running;
    final transfer = _newTransfer();
    job._transfer = transfer;
    final progress = transfer.watch().listen(
      (p) {
        job._transferred = p.transferred;
        job._total = p.total;
        _changed();
      },
      onError: (Object _) {},
    );
    try {
      job._result = await job.task.run(transfer);
      job._state = TransferState.done;
    } catch (error) {
      if (job._cancelRequested || transfer.isCancelled()) {
        job._state = TransferState.cancelled;
        await job.task.afterCancel();
      } else {
        job._state = TransferState.failed;
        job._error = FileErrors.message(error);
      }
    } finally {
      unawaited(progress.cancel());
      job._transfer = null;
      _ended(job);
      if (!_disposed) _startWaiting();
    }
  }

  /// Tells listeners a job ended, unless the queue is already gone.
  void _ended(TransferJob job) {
    if (_disposed) return;
    _finished.add(job);
    notifyListeners();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    cancelAll();
    _disposed = true;
    _finished.close();
    super.dispose();
  }
}
