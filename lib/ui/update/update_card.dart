import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../update/update_controller.dart';
import '../../update/update_scope.dart';
import '../settings/settings_widgets.dart';

/// The update offer, shown at the top of the Hosts list when a new
/// version is out and the user has not put it off. Nothing otherwise.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = UpdateScope.maybeOf(context);
    if (updates == null || !updates.supported || !updates.showCard) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: UpdateCard(controller: updates));
  }
}

/// "Version X.Y.Z is available", the release notes and what can be done
/// at each step: update, download progress, the install permission, or a
/// problem.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.controller});

  final UpdateController controller;

  static const notesHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    final release = controller.release;
    if (release == null) return const SizedBox.shrink();
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: colors.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.system_update_outlined, color: colors.accent, size: SettingsLayout.iconMedium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Version ${release.version} is available', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (controller.currentVersion != null) HelpText('You have ${controller.currentVersion}'),
                  ],
                ),
              ),
            ],
          ),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ReleaseNotes(notes: release.notes),
          ],
          const SizedBox(height: 10),
          _StepView(controller: controller),
        ],
      ),
    );
  }
}

/// The release text as plain text, scrolling inside a fixed height.
class _ReleaseNotes extends StatefulWidget {
  const _ReleaseNotes({required this.notes});

  final String notes;

  @override
  State<_ReleaseNotes> createState() => _ReleaseNotesState();
}

class _ReleaseNotesState extends State<_ReleaseNotes> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Semantics(
      label: 'Release notes',
      child: Container(
        constraints: const BoxConstraints(maxHeight: UpdateCard.notesHeight),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10)),
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(10),
            child: Text(widget.notes, style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ),
    );
  }
}

/// The part of the card that changes with each step.
class _StepView extends StatelessWidget {
  const _StepView({required this.controller});

  final UpdateController controller;

  static String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final later = TextButton(onPressed: c.later, child: const Text('Later'));
    return switch (c.phase) {
      UpdatePhase.downloading => _Busy(
          progress: c.progress,
          text: c.release!.apkSize > 0
              ? 'Downloading... ${_megabytes(c.received)} of ${_megabytes(c.release!.apkSize)} MB'
              : 'Downloading... ${_megabytes(c.received)} MB',
          action: TextButton(onPressed: c.cancelDownload, child: const Text('Cancel')),
        ),
      UpdatePhase.verifying => const _Busy(text: 'Checking that the download is genuine...'),
      UpdatePhase.needsPermission => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NoticeBox(
              tone: NoticeTone.info,
              title: 'Allow Multiplex to install the update',
              text: 'Android asks for this once. On the next screen, turn on "Allow from this source", then come back here.',
            ),
            _Actions([FilledButton(onPressed: c.openInstallPermission, child: const Text('Open settings')), later]),
          ],
        ),
      UpdatePhase.installing => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HelpText('The download is checked. Confirm the update in the Android installer.'),
            _Actions([FilledButton.tonal(onPressed: c.install, child: const Text('Open installer again')), later]),
          ],
        ),
      UpdatePhase.failed => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NoticeBox(tone: NoticeTone.error, text: c.error ?? 'The update failed.'),
            _Actions([FilledButton(onPressed: c.update, child: const Text('Try again')), later]),
          ],
        ),
      _ => _Actions([
          FilledButton(onPressed: c.update, child: const Text('Update')),
          later,
          TextButton(onPressed: c.skip, child: const Text('Skip this version')),
        ]),
    };
  }
}

/// A progress bar with what is happening and an optional button.
class _Busy extends StatelessWidget {
  const _Busy({required this.text, this.progress, this.action});

  final String text;
  final double? progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: HelpText(text)),
                ?action,
              ],
            ),
          ],
        ),
      );
}

/// Buttons in a row that wraps on narrow screens.
class _Actions extends StatelessWidget {
  const _Actions(this.buttons);

  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.end, children: buttons),
      );
}
