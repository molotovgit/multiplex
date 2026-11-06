import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../update/update_controller.dart';
import '../../update/update_scope.dart';
import '../common/widgets.dart';
import '../settings/settings_widgets.dart';
import 'update_card.dart';

/// "Updates" on the About page: the installed version, a button to check
/// now, the automatic-check switch, and the offer when there is one.
/// Shown only where in-app updates work (Android).
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = UpdateScope.maybeOf(context);
    if (updates == null || !updates.supported) return const SizedBox.shrink();
    final store = AppScope.watch(context);
    final checking = updates.phase == UpdatePhase.checking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Updates'),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Check for updates'),
          subtitle: Text(_status(updates)),
          trailing: checking ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: updates.busy ? null : () => updates.check(byHand: true),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.update),
          title: const Text('Check for updates automatically'),
          subtitle: const Text('Once a day when the app opens, from GitHub Releases'),
          value: store.settings.autoCheckUpdates,
          onChanged: (on) => store.updateSettings(store.settings.copyWith(autoCheckUpdates: on)),
        ),
        if (updates.phase == UpdatePhase.failed && updates.release == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 4, SettingsLayout.gutter, 8),
            child: NoticeBox(tone: NoticeTone.error, text: updates.error ?? 'The check failed.'),
          ),
        if (updates.showCard)
          Padding(
            padding: const EdgeInsets.fromLTRB(SettingsLayout.gutter, 4, SettingsLayout.gutter, 8),
            child: UpdateCard(controller: updates),
          ),
      ],
    );
  }

  static String _status(UpdateController u) => switch (u.phase) {
        UpdatePhase.checking => 'Checking GitHub...',
        UpdatePhase.upToDate => 'You have the newest version (${u.currentVersion})',
        _ => 'Version ${u.currentVersion} installed',
      };
}
