import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../common/widgets.dart';
import 'generate_key_form.dart';
import 'import_key_form.dart';
import 'key_tools.dart';
import 'page_width.dart';

/// Where a new key comes from.
enum KeySource { generate, import }

/// "New key": make a new key pair or bring in an existing one. Saves the
/// key in the vault and closes with it.
class KeyCreatorScreen extends StatefulWidget {
  const KeyCreatorScreen({super.key, this.tools = const NativeKeyTools()});

  final KeyTools tools;

  @override
  State<KeyCreatorScreen> createState() => _KeyCreatorScreenState();
}

class _KeyCreatorScreenState extends State<KeyCreatorScreen> {
  KeySource _source = KeySource.generate;

  void _finish(StoredKey key) {
    AppScope.store(context).saveKey(key);
    Toast.show(context, 'Saved the key "${key.name}"');
    Navigator.pop(context, key);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New key')),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            FormRow(
              child: SegmentedButton<KeySource>(
                segments: const [
                  ButtonSegment(value: KeySource.generate, icon: Icon(Icons.auto_awesome_outlined), label: Text('Generate new')),
                  ButtonSegment(value: KeySource.import, icon: Icon(Icons.file_download_outlined), label: Text('Import existing')),
                ],
                selected: {_source},
                onSelectionChanged: (choice) => setState(() => _source = choice.first),
              ),
            ),
            // Both forms stay alive, so switching back and forth does not
            // lose what was typed.
            Visibility(
              visible: _source == KeySource.generate,
              maintainState: true,
              child: GenerateKeyForm(tools: widget.tools, onCreated: _finish),
            ),
            Visibility(
              visible: _source == KeySource.import,
              maintainState: true,
              child: ImportKeyForm(tools: widget.tools, onCreated: _finish),
            ),
          ],
        ),
      ),
    );
  }
}
