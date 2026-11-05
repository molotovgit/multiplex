import 'package:flutter_test/flutter_test.dart';
import 'package:vaultterm/main.dart';

void main() {
  testWidgets('app shows its name', (tester) async {
    await tester.pumpWidget(const VaultTermApp());
    expect(find.text('VaultTerm'), findsOneWidget);
  });
}
