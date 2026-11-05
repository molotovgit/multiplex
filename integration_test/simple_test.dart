import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vaultterm/main.dart';
import 'package:vaultterm/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('app starts with the native core loaded', (tester) async {
    await tester.pumpWidget(const VaultTermApp());
    expect(find.text('VaultTerm'), findsOneWidget);
  });
}
