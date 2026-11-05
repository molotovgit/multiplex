import 'package:flutter_test/flutter_test.dart';
import 'package:vaultterm/app/vault_term_app.dart';
import 'package:vaultterm/data/vault_backend.dart';
import 'package:vaultterm/data/vault_store.dart';
import 'package:vaultterm/sessions/session_manager.dart';

void main() {
  testWidgets('the app opens on the hosts list with all five places', (tester) async {
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    await tester.pumpWidget(VaultTermApp(store: store, sessions: sessions));
    await tester.pumpAndSettle();
    for (final place in ['Hosts', 'Sessions', 'Snippets', 'Keychain', 'Settings']) {
      expect(find.text(place), findsWidgets, reason: place);
    }
    sessions.dispose();
  });
}
