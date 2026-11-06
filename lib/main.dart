import 'package:flutter/material.dart';

import 'app/terminal_fonts.dart';
import 'app/multiplex_app.dart';
import 'data/vault_backend.dart';
import 'data/vault_store.dart';
import 'platform/home_widget_sync.dart';
import 'sessions/background_keeper.dart';
import 'sessions/session_manager.dart';
import 'src/rust/frb_generated.dart';
import 'ui/settings/app_licenses.dart';

/// Starts the native core, opens the encrypted vault and shows the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLicenses.register();
  await RustLib.init();
  final store = await VaultStore.open(await EncryptedFileBackend.open());
  await TerminalFonts.loadCustomFonts(store.settings);
  final sessions = SessionManager(store);
  // Lives as long as the app: keeps connections alive in the background.
  BackgroundKeeper(sessions);
  // Keeps the home-screen widget's favourite hosts current.
  HomeWidgetSync(store);
  runApp(MultiplexApp(store: store, sessions: sessions));
}
