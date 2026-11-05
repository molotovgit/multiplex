import 'package:flutter/material.dart';

/// A short message with an Undo button, for removals that are cheap to
/// put back. It goes away on its own after a few seconds.
abstract final class UndoToast {
  static void show(BuildContext context, String message, VoidCallback onUndo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        // A bar with an action stays up by default; this one should not.
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ));
  }
}
