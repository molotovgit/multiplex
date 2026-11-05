import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../common/widgets.dart';
import '../terminal/key_bar_items.dart';
import 'key_bar_layout.dart';
import 'key_bar_preview.dart';
import 'settings_widgets.dart';

/// Lets the user choose which keys sit in the bar above the keyboard and
/// in what order. Every change is saved at once, and the preview at the
/// top shows the bar as it will look.
class KeyBarEditorScreen extends StatelessWidget {
  const KeyBarEditorScreen({super.key});

  static void _save(BuildContext context, KeyBarLayout layout) {
    final store = AppScope.store(context);
    store.updateSettings(store.settings.copyWith(keyBar: layout.ids));
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await Confirm.ask(
      context,
      title: 'Reset the key bar?',
      message: 'The bar goes back to the standard keys in the standard order.',
      action: 'Reset to default',
      destructive: false,
    );
    if (!ok || !context.mounted) return;
    _save(context, KeyBarLayout.standard());
    Toast.show(context, 'The key bar has the standard keys again');
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final layout = KeyBarLayout(store.settings.keyBar);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Key bar'),
            actions: [
              IconButton(
                icon: const Icon(Icons.restart_alt),
                tooltip: 'Reset to default',
                onPressed: layout.isStandard ? null : () => _reset(context),
              ),
            ],
          ),
          body: ContentWidth(
            child: Column(
              children: [
                const SectionHeader('Preview'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SettingsLayout.gutter),
                  child: KeyBarPreview(layout: layout),
                ),
                Expanded(child: _KeyList(layout: layout, onChanged: (next) => _save(context, next))),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The keys in the bar as a list that can be dragged into a new order.
/// Each row also has a remove button and a "Move" menu, so the order can
/// be changed without dragging.
class _KeyList extends StatelessWidget {
  const _KeyList({required this.layout, required this.onChanged});

  final KeyBarLayout layout;
  final ValueChanged<KeyBarLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = layout.items;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 24),
      header: _ListHeader(count: items.length),
      footer: _AddKeysButton(enabled: layout.missing.isNotEmpty),
      itemCount: items.length,
      onReorderItem: (from, to) => onChanged(layout.moved(from, to)),
      itemBuilder: (context, index) => _KeyRow(
        key: ValueKey(items[index].id),
        item: items[index],
        index: index,
        count: items.length,
        onMove: (to) => onChanged(layout.moved(index, to)),
        onRemove: () => onChanged(layout.without(items[index].id)),
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader('Keys in the bar', trailing: Padding(padding: const EdgeInsets.only(right: 8), child: Text('$count'))),
          Padding(
            padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 0, SettingsLayout.gutter, 8),
            child: HelpText(
              count == 0
                  ? 'The bar is empty. Add keys to show them above the keyboard.'
                  : 'Drag the handle or use Move to change the order.',
            ),
          ),
        ],
      );
}

/// Where the "Move" menu can send a key.
enum _MoveTo { up, down, start, end }

/// One key in the list: its name, remove, the Move menu, and the handle
/// to drag it. Every control is at least 48 dp with 8 dp between them.
class _KeyRow extends StatelessWidget {
  const _KeyRow({
    super.key,
    required this.item,
    required this.index,
    required this.count,
    required this.onMove,
    required this.onRemove,
  });

  final KeyBarItem item;
  final int index;
  final int count;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  bool get _isFirst => index == 0;
  bool get _isLast => index == count - 1;

  void _move(_MoveTo where) => onMove(switch (where) {
        _MoveTo.up => index - 1,
        _MoveTo.down => index + 1,
        _MoveTo.start => 0,
        _MoveTo.end => count - 1,
      });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        title: Text(item.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove ${item.name}',
              onPressed: onRemove,
            ),
            const SizedBox(width: 8),
            PopupMenuButton<_MoveTo>(
              icon: const Icon(Icons.swap_vert),
              tooltip: 'Move ${item.name}',
              enabled: count > 1,
              onSelected: _move,
              itemBuilder: (_) => [
                PopupMenuItem(value: _MoveTo.up, enabled: !_isFirst, child: const Text('Move up')),
                PopupMenuItem(value: _MoveTo.down, enabled: !_isLast, child: const Text('Move down')),
                PopupMenuItem(value: _MoveTo.start, enabled: !_isFirst, child: const Text('Move to the start')),
                PopupMenuItem(value: _MoveTo.end, enabled: !_isLast, child: const Text('Move to the end')),
              ],
            ),
            const SizedBox(width: 8),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Drag to move ${item.name}',
                child: Tooltip(
                  message: 'Drag to move',
                  excludeFromSemantics: true,
                  child: const SizedBox.square(dimension: 48, child: Icon(Icons.drag_handle)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the sheet of keys that are not in the bar yet.
class _AddKeysButton extends StatelessWidget {
  const _AddKeysButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 16, SettingsLayout.gutter, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(enabled ? 'Add key' : 'Every key is in the bar'),
            onPressed: enabled ? () => AddKeySheet.show(context) : null,
          ),
        ),
      );
}
