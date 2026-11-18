import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_motion.dart';
import '../../app/theme.dart';
import '../../sessions/desk_controller.dart';
import '../../src/rust/api/desk_types.dart';
import '../common/widgets.dart';
import '../settings/settings_widgets.dart';

/// Every key binding of the computer that has a description: search it,
/// tap one to run it, pin the ones wanted on the panel.
abstract final class BindingsSheet {
  static Future<void> show(
    BuildContext context, {
    required DeskController controller,
    required List<String> pins,
    required ValueChanged<List<String>> onPinsChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: AppMotion.of(context).sheet,
      builder: (_) => _Bindings(controller: controller, pins: pins, onPinsChanged: onPinsChanged),
    );
  }
}

class _Bindings extends StatefulWidget {
  const _Bindings({required this.controller, required this.pins, required this.onPinsChanged});

  final DeskController controller;
  final List<String> pins;
  final ValueChanged<List<String>> onPinsChanged;

  @override
  State<_Bindings> createState() => _BindingsState();
}

class _BindingsState extends State<_Bindings> {
  final _search = TextEditingController();
  late final List<String> _pins = [...widget.pins];
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _pinned(DeskBinding b) => _pins.any((keys) => b.keys == keys || b.keys.split(' / ').contains(keys));

  void _togglePin(DeskBinding b) {
    setState(() {
      if (_pinned(b)) {
        _pins.removeWhere((keys) => b.keys == keys || b.keys.split(' / ').contains(keys));
      } else {
        _pins.add(b.keys);
      }
    });
    widget.onPinsChanged([..._pins]);
  }

  Future<void> _run(DeskBinding b) async {
    HapticFeedback.selectionClick();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.controller.run(DeskAction.bind(keys: b.keys));
    if (ok) {
      navigator.pop();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(widget.controller.problem ?? 'The computer did not answer.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final all = widget.controller.bindings;
        final q = _query.toLowerCase();
        final shown = [
          for (final b in all ?? const <DeskBinding>[])
            if (q.isEmpty || b.title.toLowerCase().contains(q) || b.keys.toLowerCase().contains(q)) b,
        ];
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Search the shortcuts',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (v) => setState(() => _query = v.trim()),
                  trailing: [
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                  ],
                ),
              ),
              Expanded(
                child: all == null
                    ? const Center(child: BusyNote('Reading the computer\'s shortcuts…'))
                    : shown.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            all.isEmpty ? 'This computer lists no shortcuts.' : 'No shortcut matches. Try a name or a key.',
                            style: TextStyle(color: colors.muted),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final b = shown[i];
                          final pinned = _pinned(b);
                          return ListTile(
                            title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: MonoText(b.keys),
                            enabled: b.run,
                            onTap: b.run ? () => _run(b) : null,
                            trailing: b.run
                                ? IconButton(
                                    tooltip: pinned ? 'Unpin ${b.title} from the panel' : 'Pin ${b.title} to the panel',
                                    isSelected: pinned,
                                    icon: const Icon(Icons.push_pin_outlined),
                                    selectedIcon: Icon(Icons.push_pin, color: colors.accent),
                                    onPressed: () => _togglePin(b),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
