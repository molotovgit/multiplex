import 'package:flutter/services.dart';

/// Something Android asked the app to do from outside: a tap on a host in
/// the home-screen widget, or files shared from another app.
sealed class IncomingAction {
  const IncomingAction();

  /// Reads one action as the native side sends it. Null for anything not
  /// understood.
  static IncomingAction? parse(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'connect':
        final id = raw['hostId'];
        return id is String && id.isNotEmpty ? ConnectAction(id) : null;
      case 'share':
        final files = raw['files'];
        if (files is! List) return null;
        final parsed = [
          for (final f in files)
            if (f is Map && f['name'] is String && f['path'] is String) SharedFile(name: f['name'] as String, path: f['path'] as String),
        ];
        final text = raw['text'];
        return parsed.isEmpty ? null : ShareAction(parsed, text: text is String && text.isNotEmpty ? text : null);
      case 'shareFailed':
        return const ShareFailedAction();
    }
    return null;
  }
}

/// Open a terminal on a saved host.
class ConnectAction extends IncomingAction {
  const ConnectAction(this.hostId);

  final String hostId;
}

/// Upload these files to a server. The native side has already copied
/// each one into the app's cache, at [SharedFile.path].
class ShareAction extends IncomingAction {
  const ShareAction(this.files, {this.text});

  final List<SharedFile> files;

  /// Set when text (a link, a note) was shared rather than files; [files]
  /// then holds it as one text file, for servers.
  final String? text;
}

/// Something was shared, but none of it could be read.
class ShareFailedAction extends IncomingAction {
  const ShareFailedAction();
}

class SharedFile {
  const SharedFile({required this.name, required this.path});

  final String name;
  final String path;
}

/// The channel the native side queues actions on. It says "changed" when
/// a new one is waiting; [take] collects all of them.
class IncomingChannel {
  IncomingChannel([this._channel = const MethodChannel('multiplex/incoming')]);

  final MethodChannel _channel;

  /// Calls [onChanged] whenever the native side has something new.
  void listen(void Function() onChanged) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') onChanged();
    });
  }

  void stop() => _channel.setMethodCallHandler(null);

  /// The waiting actions (and clears them on the native side).
  Future<List<IncomingAction>> take() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('take');
      return [for (final item in raw ?? const []) ?IncomingAction.parse(item)];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
