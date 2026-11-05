import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Saved commands.
class SnippetsScreen extends StatelessWidget {
  const SnippetsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Snippets')));
}

/// Bottom sheet to pick a snippet to run in a terminal.
abstract final class SnippetPicker {
  static Future<Snippet?> show(BuildContext context) async => null;
}
