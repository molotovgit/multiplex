import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../common/widgets.dart';

/// Asks which saved host to use, in a bottom sheet.
abstract final class HostPicker {
  /// Returns the chosen host, or null if the sheet was closed.
  static Future<Host?> pick(BuildContext context, {required String title}) {
    return showModalBottomSheet<Host>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => HostPickerSheet(title: title),
    );
  }
}

/// The list of saved hosts; tapping one closes the sheet with it.
class HostPickerSheet extends StatelessWidget {
  const HostPickerSheet({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final hosts = [...AppScope.store(context).hosts]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (hosts.isEmpty)
            const EmptyState(
              icon: Icons.dns_outlined,
              title: 'No saved hosts',
              message: 'Add a server on the Hosts screen first, then come back here.',
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                children: [for (final host in hosts) HostChoiceTile(host: host)],
              ),
            ),
        ],
      ),
    );
  }
}

/// One host in the picker. The dot shows whether it is already connected.
class HostChoiceTile extends StatelessWidget {
  const HostChoiceTile({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context) {
    final connected = AppScope.sessions(context).sessionFor(host.id) != null;
    return ListTile(
      leading: StatusDot(live: connected, size: 10),
      title: Text(host.title),
      subtitle: MonoText(host.target, maxLines: 1),
      onTap: () => Navigator.pop(context, host),
    );
  }
}
