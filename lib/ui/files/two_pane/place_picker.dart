import 'package:flutter/material.dart';

import '../../../app/app_motion.dart';
import '../../../app/theme.dart';
import '../../../data/models.dart';
import '../../common/widgets.dart';
import 'phone_storage.dart';

/// What the user picked for a pane.
sealed class PlaceChoice {
  const PlaceChoice();
}

class PhonePlace extends PlaceChoice {
  const PhonePlace(this.root);

  final PhoneRoot root;
}

class ServerPlace extends PlaceChoice {
  const ServerPlace(this.host);

  final Host host;
}

/// The user wants the whole phone storage, which needs Android's "all
/// files" access first.
class AllowAccessPlace extends PlaceChoice {
  const AllowAccessPlace();
}

/// A sheet listing this phone's folders and the saved servers.
class PlacePicker extends StatelessWidget {
  const PlacePicker({super.key, required this.roots, required this.hosts, required this.connected, required this.offerAccess});

  final List<PhoneRoot> roots;
  final List<Host> hosts;

  /// Ids of hosts with an open connection, marked with a dot.
  final Set<String> connected;

  /// Shows "Whole phone storage" for a phone without all-files access yet.
  final bool offerAccess;

  static Future<PlaceChoice?> show(
    BuildContext context, {
    required List<PhoneRoot> roots,
    required List<Host> hosts,
    required Set<String> connected,
    required bool offerAccess,
  }) => showModalBottomSheet<PlaceChoice>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: AppMotion.of(context).sheet,
    builder: (_) => PlacePicker(roots: roots, hosts: hosts, connected: connected, offerAccess: offerAccess),
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            const SectionHeader('This phone'),
            for (final root in roots)
              ListTile(
                leading: Icon(root.icon),
                title: Text(root.label),
                subtitle: root.note == null ? null : Text(root.note!),
                onTap: () => Navigator.pop(context, PhonePlace(root)),
              ),
            if (offerAccess)
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: const Text('Whole phone storage'),
                subtitle: const Text('Needs Android\'s "All files access" for Multiplex. Opens the setting.'),
                onTap: () => Navigator.pop(context, const AllowAccessPlace()),
              ),
            const SectionHeader('Servers'),
            if (hosts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text('No saved servers yet. Add one on the Hosts screen.', style: TextStyle(color: colors.muted)),
              ),
            for (final host in hosts)
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(host.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(host.target, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: connected.contains(host.id) ? Semantics(label: 'Connected', child: const StatusDot(live: true)) : null,
                onTap: () => Navigator.pop(context, ServerPlace(host)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
