import 'package:flutter/material.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';
import '../terminal/key_bar_items.dart';
import 'key_bar_layout.dart';
import 'settings_widgets.dart';

/// One key drawn the way it looks in the bar: its icon, or its short
/// label in the terminal font.
class KeyCap extends StatelessWidget {
  const KeyCap(this.item, {super.key});

  final KeyBarItem item;

  /// Height of a key at normal text size.
  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.text);
    return Container(
      // A minimum, not a fixed height, so large system text still fits.
      constraints: const BoxConstraints(minWidth: 40, minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outline),
      ),
      child: item.icon != null
          ? Icon(item.icon, size: SettingsLayout.iconMedium, color: colors.text)
          : MonoText(item.label, style: textStyle),
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
    // The bar grows with the user's text size so labels are never cut.
    final height = MediaQuery.textScalerOf(context).scale(KeyCap.height).clamp(KeyCap.height, 96.0) + 16;
    return Semantics(
      label: layout.isEmpty ? 'Key bar preview: empty' : 'Key bar preview: ${items.map((i) => i.name).join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outline),
          ),
          child: layout.isEmpty
              ? const Center(child: HelpText('The bar is empty'))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
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

  /// Opens the sheet, kept clear of the system bars.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: AppMotion.of(context).sheet,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const AddKeySheet(),
      );

  void _add(BuildContext context, KeyBarItem item) {
    final store = AppScope.store(context);
    final layout = KeyBarLayout(store.settings.keyBar).withKey(item.id);
    store.updateSettings(store.settings.copyWith(keyBar: layout.ids));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
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
                  padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add keys',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
                    ],
                  ),
                ),
                Expanded(
                  child: missing.isEmpty
                      ? const Center(
                          child: Padding(padding: EdgeInsets.all(24), child: HelpText('Every key is already in the bar.')),
                        )
                      : ListView(
                          controller: scroll,
                          padding: const EdgeInsets.only(bottom: 16),
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
      ),
    );
  }
}
