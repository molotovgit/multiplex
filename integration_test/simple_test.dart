import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:multiplex/src/rust/api/app.dart';
import 'package:multiplex/src/rust/api/keys.dart';
import 'package:multiplex/src/rust/frb_generated.dart';

/// Runs on a real device or desktop with the native library loaded.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  test('the native core loads and answers', () async {
    expect(coreVersion(), isNotEmpty);
    final key = await generateKey(kind: KeyKind.ed25519, comment: 'device-test');
    expect(key.publicOpenssh, startsWith('ssh-ed25519 '));
  });
}
