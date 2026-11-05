import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/app/multiplex_app.dart';
import 'package:multiplex/data/vault_backend.dart';
import 'package:multiplex/data/vault_store.dart';
import 'package:multiplex/sessions/session_manager.dart';

void main() {
  testWidgets('the app opens on the hosts list with all five places', (tester) async {
    final store = await VaultStore.open(MemoryBackend());
    final sessions = SessionManager(store);
    await tester.pumpWidget(MultiplexApp(store: store, sessions: sessions));
    await tester.pumpAndSettle();
    for (final place in ['Hosts', 'Sessions', 'Snippets', 'Keychain', 'Settings']) {
      expect(find.text(place), findsWidgets, reason: place);
    }
    sessions.dispose();
  });
}
