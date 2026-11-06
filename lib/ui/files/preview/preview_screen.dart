import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../src/rust/api/sftp.dart';
import '../../../src/rust/api/sftp_types.dart';
import '../../common/widgets.dart';
import '../file_format.dart';
import 'pdf_document.dart';
import 'pdf_viewer.dart';
import 'preview_files.dart';
import 'zoom_view.dart';

/// Shows a picture or PDF from the server without saving it: the file is
/// fetched into a temporary copy that is deleted when this screen closes.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.files, required this.entry, required this.kind, this.onDownload, this.newTransfer, this.previewFiles});

  final RemoteFiles files;
  final RemoteEntry entry;
  final PreviewKind kind;

  /// Saves the file on this device for good.
  final VoidCallback? onDownload;
  final FileTransfer Function()? newTransfer;
  final PreviewFiles? previewFiles;

  /// Makes the transfer when [newTransfer] is not given; tests swap in a fake.
  static FileTransfer Function() defaultTransfer = FileTransfer.create;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  FileTransfer? _transfer;
  StreamSubscription<TransferProgress>? _progress;
  BigInt _done = BigInt.zero;
  BigInt _total = BigInt.zero;
  File? _file;
  PdfDocument? _pdf;
  String? _error;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _closed = true;
    // Leaving while it is still coming stops the transfer.
    if (_file == null) _transfer?.cancel();
    _progress?.cancel();
    _pdf?.close();
    PreviewFiles.discard(_file);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _done = BigInt.zero;
    });
    final transfer = _transfer = (widget.newTransfer ?? PreviewScreen.defaultTransfer)();
    await _progress?.cancel();
    _progress = transfer.watch().listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _done = p.transferred;
          _total = p.total;
        });
      },
      onError: (Object _) {},
    );
    try {
      final file = await (widget.previewFiles ?? PreviewFiles()).fetch(widget.files, widget.entry, transfer);
      if (_closed) {
        await PreviewFiles.discard(file);
        return;
      }
      _file = file;
      if (widget.kind == PreviewKind.pdf) {
        if (!PdfDocument.supported) throw const _NoPdfHere();
        final pdf = await PdfDocument.open(file.path);
        if (_closed) {
          await pdf.close();
          return;
        }
        _pdf = pdf;
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is _NoPdfHere ? error.message : FileErrors.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final download = widget.onDownload;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (download != null)
            IconButton(
              tooltip: 'Download to this device',
              icon: const Icon(Icons.download_outlined),
              onPressed: () {
                download();
                Toast.show(context, 'Downloading ${widget.entry.name}');
              },
            ),
        ],
      ),
      backgroundColor: colors.background,
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final error = _error;
    if (error != null) {
      return EmptyState(
        icon: Icons.broken_image_outlined,
        title: 'Could not show "${widget.entry.name}"',
        message: error,
        actionLabel: _file == null ? 'Try again' : null,
        onAction: _file == null ? _load : null,
      );
    }
    final file = _file;
    if (file == null) return _Fetching(name: widget.entry.name, done: _done, total: _total);
    final pdf = _pdf;
    if (pdf != null) return PdfViewer(document: pdf);
    return ZoomView(
      child: Center(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          semanticLabel: widget.entry.name,
          errorBuilder: (context, _, _) => const EmptyState(
            icon: Icons.broken_image_outlined,
            title: 'This picture cannot be shown',
            message: 'The file may be damaged or in a format this phone does not read. Download it to open it in another app.',
          ),
        ),
      ),
    );
  }
}

/// The file is still coming: how much so far.
class _Fetching extends StatelessWidget {
  const _Fetching({required this.name, required this.done, required this.total});

  final String name;
  final BigInt done;
  final BigInt total;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final fraction = total > BigInt.zero ? (done / total).clamp(0.0, 1.0) : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Opening $name', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: fraction, semanticsLabel: 'Fetching $name'),
              const SizedBox(height: 8),
              Text(FileSizes.progress(done, total), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
              const SizedBox(height: 8),
              Text('Nothing is saved on this device.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoPdfHere implements Exception {
  const _NoPdfHere();

  String get message => 'PDF preview works on Android phones and tablets. Download the file to open it on this device.';
}
