import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';
import '../terminal/key_bar_items.dart';
import 'key_bar_layout.dart';

/// One key drawn the way it looks in the bar: its icon, or its short
/// label in the terminal font.
class KeyCap extends StatelessWidget {
  const KeyCap(this.item, {super.key});

  final KeyBarItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.text);
    return Container(
      constraints: const BoxConstraints(minWidth: 40),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outline),
      ),
      child: item.icon != null ? Icon(item.icon, size: 18, color: colors.text) : MonoText(item.label, style: textStyle),
    );
  }
}

/// The bar as it will look above the keyboard. It scrolls sideways when
/// the keys do not fit, just like the real bar.
class KeyBarPreview extends StatelessWidget {
  const KeyBarPreview({super.key, required this.layout});

  final KeyBarLayout layout;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final items = layout.items;
    return Semantics(
      label: layout.isEmpty ? 'Key bar preview: empty' : 'Key bar preview: ${items.map((i) => i.name).join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outline),
          ),
          child: layout.isEmpty
              ? Center(child: Text('The bar is empty', style: TextStyle(color: colors.muted)))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, index) => KeyCap(items[index]),
                ),
        ),
      ),
    );
  }
}

/// A sheet listing the keys not yet in the bar. Tapping one adds it at the
/// end straight away; the sheet stays open so several can be added.
class AddKeySheet extends StatelessWidget {
  const AddKeySheet({super.key});

  void _add(BuildContext context, KeyBarItem item) {
    final store = AppScope.store(context);
    final layout = KeyBarLayout(store.settings.keyBar).withKey(item.id);
    store.updateSettings(store.settings.copyWith(keyBar: layout.ids));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    final colors = AppColorsTheme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final missing = KeyBarLayout(store.settings.keyBar).missing;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('Add keys', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                  ],
                ),
              ),
              Expanded(
                child: missing.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Every key is already in the bar.', style: TextStyle(color: colors.muted)),
                        ),
                      )
                    : ListView(
                        controller: scroll,
                        children: [
                          for (final item in missing)
                            ListTile(
                              key: ValueKey('add-${item.id}'),
                              leading: SizedBox(width: 64, child: Align(alignment: Alignment.centerLeft, child: KeyCap(item))),
                              title: Text(item.name),
                              trailing: const Icon(Icons.add),
                              onTap: () => _add(context, item),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
