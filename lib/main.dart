import 'package:flutter/material.dart';

import 'app/terminal_fonts.dart';
import 'app/vault_term_app.dart';
import 'data/vault_backend.dart';
import 'data/vault_store.dart';
import 'sessions/session_manager.dart';
import 'src/rust/frb_generated.dart';

/// Starts the native core, opens the encrypted vault and shows the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final store = await VaultStore.open(await EncryptedFileBackend.open());
  await TerminalFonts.loadCustomFonts(store.settings);
  runApp(VaultTermApp(store: store, sessions: SessionManager(store)));
}
