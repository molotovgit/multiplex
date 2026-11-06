import '../../../data/sync_pairs.dart';
import '../../../src/rust/api/sftp.dart';
import '../../../src/rust/api/transfer.dart';
import '../../../src/rust/api/transfer_types.dart';

/// Compares and syncs a pair's folders. The phone folder is the left
/// side, the server folder the right one. Tests use a fake.
abstract interface class SyncBackend {
  Future<List<SyncAction>> plan(SyncPair pair, FileTransfer transfer);

  Future<SyncReport> apply(SyncPair pair, List<SyncAction> actions, FileTransfer transfer);
}

/// The real thing, through the Rust core.
class CoreSyncBackend implements SyncBackend {
  CoreSyncBackend(RemoteFiles files) : _server = FileSide.server(files: files), _phone = FileSide.phone();

  final FileSide _server;
  final FileSide _phone;

  static SyncDirection directionOf(SyncWay way) => switch (way) {
    SyncWay.toServer => SyncDirection.toRight,
    SyncWay.toPhone => SyncDirection.toLeft,
    SyncWay.both => SyncDirection.both,
  };

  @override
  Future<List<SyncAction>> plan(SyncPair pair, FileTransfer transfer) => syncPlan(
    left: _phone,
    leftRoot: pair.phonePath,
    right: _server,
    rightRoot: pair.serverPath,
    direction: directionOf(pair.way),
    mirror: pair.mirrors,
    transfer: transfer,
  );

  @override
  Future<SyncReport> apply(SyncPair pair, List<SyncAction> actions, FileTransfer transfer) =>
      syncApply(left: _phone, leftRoot: pair.phonePath, right: _server, rightRoot: pair.serverPath, actions: actions, transfer: transfer);
}

/// Words for a sync step.
abstract final class SyncWords {
  static String kind(SyncActionKind kind) => switch (kind) {
    SyncActionKind.copyToRight => 'Copy to the server',
    SyncActionKind.copyToLeft => 'Copy to the phone',
    SyncActionKind.deleteOnRight => 'Delete on the server',
    SyncActionKind.deleteOnLeft => 'Delete on the phone',
    SyncActionKind.conflict => 'Needs you: left alone',
  };

  static String reason(SyncReason reason) => switch (reason) {
    SyncReason.new_ => 'Only on one side',
    SyncReason.changed => 'Size or time differs',
    SyncReason.newer => 'Newer on this side',
    SyncReason.extra => 'Not in the source folder',
    SyncReason.typeClash => 'A file on one side, a folder on the other',
    SyncReason.undecided => 'Different, and neither is clearly newer',
  };

  static bool isDelete(SyncAction a) => a.kind == SyncActionKind.deleteOnLeft || a.kind == SyncActionKind.deleteOnRight;
}
