import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import 'key_creator_screen.dart';
import 'key_tools.dart';
import 'keys_tab.dart';
import 'known_hosts_tab.dart';

/// Keys and known hosts, on two tabs.
class KeychainScreen extends StatefulWidget {
  const KeychainScreen({super.key, this.tools = const NativeKeyTools()});

  /// Key operations; tests pass a stand-in.
  final KeyTools tools;

  @override
  State<KeychainScreen> createState() => _KeychainScreenState();
}

class _KeychainScreenState extends State<KeychainScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _newKey() => KeyCreator.open(context, tools: widget.tools);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keychain'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Keys'), Tab(text: 'Known hosts')]),
      ),
      // The button belongs to the Keys tab, and is left out while the
      // empty list already offers the same action.
      floatingActionButton: ListenableBuilder(
        listenable: Listenable.merge([_tabs, store]),
        builder: (context, _) => _tabs.index == 0 && store.keys.isNotEmpty
            ? FloatingActionButton.extended(onPressed: _newKey, icon: const Icon(Icons.add), label: const Text('New key'))
            : const SizedBox.shrink(),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [KeysTab(tools: widget.tools, onNewKey: _newKey), const KnownHostsTab()],
      ),
    );
  }
}

/// Creates or imports a key from anywhere in the app (for example the host
/// editor) and returns it, already saved in the vault, or null if the user
/// went back without saving.
abstract final class KeyCreator {
  static Future<StoredKey?> open(BuildContext context, {KeyTools tools = const NativeKeyTools()}) {
    return Navigator.of(context).push<StoredKey>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => KeyCreatorScreen(tools: tools)),
    );
  }
}
