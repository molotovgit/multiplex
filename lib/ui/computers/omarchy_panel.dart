import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../../sessions/clipboard_picture.dart';
import '../../sessions/desk_controller.dart';
import '../../src/rust/api/desk_types.dart';
import '../common/widgets.dart';
import '../settings/settings_widgets.dart';
import 'bindings_sheet.dart';

/// The computer's desktop without its picture: workspaces, the window in
/// focus, launchers and media, each one tap away. It does what the
/// computer's own keys do, so it feels the same from the phone.
///
/// Used as a page of its own and inside the remote desktop (at the bottom
/// in portrait, at the side in landscape), so it sizes to its content and
/// leaves scrolling to whoever holds it.
class OmarchyPanel extends StatefulWidget {
  const OmarchyPanel({
    super.key,
    required this.controller,
    required this.pins,
    required this.onPinsChanged,
    this.dense = false,
    this.readClipboard,
    this.writeClipboard,
    this.readPicture,
    this.writePicture,
  });

  /// The phone's clipboard. Replaced in tests.
  final Future<String?> Function()? readClipboard;
  final Future<void> Function(String text)? writeClipboard;

  /// The same for a picture on the phone's clipboard. Tests replace them.
  final Future<ClipboardPicture?> Function()? readPicture;
  final Future<void> Function(ClipboardPicture picture)? writePicture;

  final DeskController controller;

  /// The pinned bindings, by their keys. Empty means the usual four.
  final List<String> pins;
  final ValueChanged<List<String>> onPinsChanged;

  /// Inside the remote desktop: tighter, without section headings.
  final bool dense;

  /// Pinned until the user chooses: Omarchy's menu, a terminal, the
  /// browser and the file manager.
  static const usualPins = ['SUPER + SPACE', 'SUPER + RETURN', 'SUPER SHIFT + RETURN', 'SUPER SHIFT + F'];

  @override
  State<OmarchyPanel> createState() => _OmarchyPanelState();
}

class _OmarchyPanelState extends State<OmarchyPanel> {
  /// The arrows swap the window with its neighbour instead of moving the focus.
  bool _moveWindows = false;

  DeskController get c => widget.controller;

  Future<void> _run(DeskAction action, {String? done}) async {
    HapticFeedback.selectionClick();
    final ok = await c.run(action);
    if (ok && done != null && mounted) Toast.show(context, done);
  }

  void _arrow(DeskDirection direction) => _run(_moveWindows ? DeskAction.swap(direction: direction) : DeskAction.focus(direction: direction));

  Future<void> _allShortcuts() async {
    await c.loadBindings();
    if (!mounted) return;
    await BindingsSheet.show(context, controller: c, pins: _pins, onPinsChanged: widget.onPinsChanged);
  }

  List<String> get _pins => widget.pins.isEmpty ? OmarchyPanel.usualPins : widget.pins;

  /// What is on the phone's clipboard goes onto the computer's.
  Future<void> _sendClipboard() async {
    // Sent exactly as it is: a clipboard's spaces and line ends are its own.
    final text = await (widget.readClipboard ?? _phoneClipboard)() ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      // No text: it may hold a picture.
      final picture = await (widget.readPicture ?? PhoneClipboardPictures.read)();
      if (!mounted) return;
      if (picture == null) {
        Toast.show(context, 'The phone\'s clipboard has no text or picture');
      } else if (await c.copyPictureToComputer(picture) && mounted) {
        Toast.show(context, 'The picture is on the computer\'s clipboard now');
      }
      return;
    }
    if (await c.copyToComputer(text) && mounted) Toast.show(context, 'On the computer\'s clipboard now');
  }

  /// What is on the computer's clipboard comes onto the phone's.
  Future<void> _fetchClipboard() async {
    final text = await c.computerClipboard();
    if (!mounted || c.problem != null) return;
    if (text == null || text.isEmpty) {
      // No text: it may hold a picture.
      final picture = await c.computerPicture();
      if (!mounted || c.problem != null) return;
      if (picture == null) {
        Toast.show(context, 'The computer\'s clipboard has no text or picture');
      } else {
        await (widget.writePicture ?? PhoneClipboardPictures.write)(picture);
        if (mounted) Toast.show(context, 'The picture is on the phone\'s clipboard now');
      }
      return;
    }
    await (widget.writeClipboard ?? ((String t) => Clipboard.setData(ClipboardData(text: t))))(text);
    if (mounted) Toast.show(context, 'On the phone\'s clipboard now');
  }

  static Future<String?> _phoneClipboard() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final state = c.state;
        final problem = c.problem;
        final gap = SizedBox(height: widget.dense ? 10 : 4);
        if (state == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: problem == null
                ? const Center(child: BusyNote('Asking the computer…'))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NoticeBox(tone: NoticeTone.error, text: problem),
                      const SizedBox(height: 12),
                      Align(
                        child: FilledButton.tonal(onPressed: c.start, child: const Text('Try again')),
                      ),
                    ],
                  ),
          );
        }
        final focused = state.monitors.where((m) => m.focused).firstOrNull ?? state.monitors.firstOrNull;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (problem != null) ...[NoticeBox(tone: NoticeTone.error, text: problem), const SizedBox(height: 8)],
            if (!widget.dense) const _Heading('Workspaces'),
            if (state.monitors.length > 1) ...[
              _MonitorChips(
                monitors: state.monitors,
                onSelect: (name) => _run(DeskAction.focusMonitor(name: name)),
              ),
              const SizedBox(height: 8),
            ],
            if (focused != null)
              _Workspaces(
                monitor: focused,
                onShow: (slot) => _run(DeskAction.workspace(slot: slot, monitor: focused.name)),
                onMoveWindow: (slot) => _run(DeskAction.moveWindow(slot: slot), done: 'Moved the window to workspace $slot'),
              ),
            gap,
            if (!widget.dense) const _Heading('Window'),
            _WindowPad(
              window: state.window,
              moveWindows: _moveWindows,
              onMode: () => setState(() => _moveWindows = !_moveWindows),
              onArrow: _arrow,
              onAction: _run,
              dense: widget.dense,
            ),
            gap,
            if (!widget.dense) const _Heading('Open'),
            _Launchers(
              bindings: c.bindings,
              pins: _pins,
              onRun: (b) => _run(DeskAction.bind(keys: b.keys)),
              onAll: _allShortcuts,
            ),
            gap,
            if (!widget.dense) const _Heading('Clipboard and quiet'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.content_paste_go_outlined, size: 18),
                  label: const Text('Phone to computer'),
                  tooltip: 'Put the phone\'s clipboard on the computer\'s',
                  onPressed: _sendClipboard,
                ),
                ActionChip(
                  avatar: const Icon(Icons.content_paste_outlined, size: 18),
                  label: const Text('Computer to phone'),
                  tooltip: 'Put the computer\'s clipboard on the phone\'s',
                  onPressed: _fetchClipboard,
                ),
                // Silence the computer's notifications from here.
                if (state.dnd case final dnd?)
                  FilterChip(
                    avatar: Icon(dnd ? Icons.notifications_off_outlined : Icons.notifications_none, size: 18),
                    label: const Text('Do Not Disturb'),
                    tooltip: dnd ? 'Notifications are silenced on the computer: tap to let them through' : 'Silence the computer\'s notifications',
                    selected: dnd,
                    showCheckmark: false,
                    onSelected: (on) => _run(DeskAction.dnd(enabled: on)),
                  ),
              ],
            ),
            if (state.media != null || state.volume != null) ...[
              gap,
              if (!widget.dense) const _Heading('Sound'),
              _Media(media: state.media, volume: state.volume, onAction: _run),
            ],
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.muted, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MonitorChips extends StatelessWidget {
  const _MonitorChips({required this.monitors, required this.onSelect});

  final List<DeskMonitor> monitors;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // Wrapped, not scrolled: the monitor in focus is always in sight.
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final m in monitors)
          ChoiceChip(
            avatar: const Icon(Icons.monitor, size: 18),
            label: Text(m.name),
            tooltip: m.focused ? '${m.name} has the focus' : 'Give ${m.name} the focus',
            selected: m.focused,
            showCheckmark: false,
            onSelected: (_) => onSelect(m.name),
          ),
      ],
    );
  }
}

/// A monitor's ten workspaces: tap to show one, hold to send the window
/// in focus there.
class _Workspaces extends StatelessWidget {
  const _Workspaces({required this.monitor, required this.onShow, required this.onMoveWindow});

  final DeskMonitor monitor;
  final ValueChanged<int> onShow;
  final ValueChanged<int> onMoveWindow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // One row when there is room for ten comfortable buttons.
        final perRow = constraints.maxWidth >= 520 ? 10 : 5;
        final rows = [for (var i = 0; i < monitor.slots.length; i += perRow) monitor.slots.sublist(i, (i + perRow).clamp(0, monitor.slots.length))];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, row) in rows.indexed) ...[
              if (index > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (final (i, slot) in row.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _SlotButton(slot: slot, onTap: () => onShow(slot.slot), onHold: () => onMoveWindow(slot.slot)),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({required this.slot, required this.onTap, required this.onHold});

  final DeskSlot slot;
  final VoidCallback onTap;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final look = AppStyleTheme.of(context);
    final fg = slot.active ? colors.onAccent : (slot.windows > 0 ? colors.text : colors.muted);
    final windows = switch (slot.windows) {
      0 => 'empty',
      1 => '1 window',
      final n => '$n windows',
    };
    return Semantics(
      button: true,
      selected: slot.active,
      label: 'Workspace ${slot.slot}, $windows',
      hint: 'Hold to move the window in focus here',
      child: Material(
        color: slot.active ? colors.accent : look.surfaces.card,
        shape: look.shapes.border(look.shapes.card, slot.active ? BorderSide.none : look.surfaces.side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onHold();
          },
          child: SizedBox(
            height: 48,
            child: ExcludeSemantics(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text('${slot.slot}', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg)),
                  // A dot: this workspace has windows.
                  if (slot.windows > 0)
                    Positioned(
                      bottom: 6,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: slot.active ? colors.onAccent : colors.accent),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The window in focus: arrows to go to (or swap with) its neighbours,
/// and the four things done to a window all day.
class _WindowPad extends StatelessWidget {
  const _WindowPad({required this.window, required this.moveWindows, required this.onMode, required this.onArrow, required this.onAction, this.dense = false});

  final DeskWindow? window;
  final bool moveWindows;
  final VoidCallback onMode;
  final ValueChanged<DeskDirection> onArrow;
  final ValueChanged<DeskAction> onAction;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final window = this.window;
    final what = moveWindows ? 'Move the window' : 'Focus the window';
    // Inside the desktop the panel is narrow: smaller arrows leave the words room.
    final density = dense ? VisualDensity.compact : VisualDensity.standard;
    Widget arrow(IconData icon, DeskDirection direction, String where) =>
        IconButton.filledTonal(tooltip: '$what $where', visualDensity: density, icon: Icon(icon), onPressed: () => onArrow(direction));
    // Four buttons share the width left of the arrows: little padding, so the words fit.
    final tight = FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 44));
    Widget action(IconData icon, String label, DeskAction action, {bool on = false}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: on
            ? FilledButton.icon(
                style: tight,
                onPressed: () => onAction(action),
                icon: Icon(icon, size: 18),
                label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              )
            : FilledButton.tonalIcon(
                style: tight,
                onPressed: window == null ? null : () => onAction(action),
                icon: Icon(icon, size: 18),
                label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          window == null ? 'No window in focus' : (window.title.isEmpty ? window.class_ : window.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(color: window == null ? colors.muted : colors.text),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The arrows, laid out as on a keyboard, with the mode between them.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                arrow(Icons.keyboard_arrow_up, DeskDirection.up, 'above'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    arrow(Icons.keyboard_arrow_left, DeskDirection.left, 'on the left'),
                    IconButton(
                      visualDensity: density,
                      tooltip: moveWindows
                          ? 'The arrows move the window: switch to moving the focus'
                          : 'The arrows move the focus: switch to moving the window',
                      isSelected: moveWindows,
                      icon: const Icon(Icons.center_focus_weak),
                      selectedIcon: Icon(Icons.open_with, color: colors.accent),
                      onPressed: onMode,
                    ),
                    arrow(Icons.keyboard_arrow_right, DeskDirection.right, 'on the right'),
                  ],
                ),
                arrow(Icons.keyboard_arrow_down, DeskDirection.down, 'below'),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      action(Icons.close, 'Close', const DeskAction.close()),
                      action(Icons.fullscreen, 'Full', const DeskAction.fullscreen(), on: window?.fullscreen ?? false),
                    ],
                  ),
                  Row(
                    children: [
                      action(Icons.picture_in_picture_alt_outlined, 'Float', const DeskAction.float(), on: window?.floating ?? false),
                      action(Icons.vertical_split_outlined, 'Split', const DeskAction.split()),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The pinned bindings, and the way to all the others.
class _Launchers extends StatelessWidget {
  const _Launchers({required this.bindings, required this.pins, required this.onRun, required this.onAll});

  final List<DeskBinding>? bindings;
  final List<String> pins;
  final ValueChanged<DeskBinding> onRun;
  final VoidCallback onAll;

  static bool _is(DeskBinding binding, String keys) => binding.keys == keys || binding.keys.split(' / ').contains(keys);

  @override
  Widget build(BuildContext context) {
    final all = bindings ?? const <DeskBinding>[];
    final pinned = [for (final keys in pins) ?all.where((b) => b.run && _is(b, keys)).firstOrNull];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final b in pinned) ActionChip(label: Text(b.title), tooltip: b.keys, onPressed: () => onRun(b)),
        ActionChip(
          avatar: const Icon(Icons.keyboard_command_key, size: 18),
          label: const Text('All shortcuts'),
          tooltip: 'Every key binding of the computer',
          onPressed: onAll,
        ),
      ],
    );
  }
}

/// What is playing, with the keyboard's media keys.
class _Media extends StatelessWidget {
  const _Media({required this.media, required this.volume, required this.onAction});

  final DeskMedia? media;
  final DeskVolume? volume;
  final ValueChanged<DeskAction> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final media = this.media;
    final volume = this.volume;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (media != null)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.title.isEmpty ? media.player : media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                    Text(
                      media.artist.isEmpty || media.title.isEmpty ? media.player : '${media.artist} · ${media.player}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Previous track', icon: const Icon(Icons.skip_previous), onPressed: () => onAction(const DeskAction.previous())),
              IconButton.filledTonal(
                tooltip: media.playing ? 'Pause' : 'Play',
                icon: Icon(media.playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => onAction(const DeskAction.playPause()),
              ),
              IconButton(tooltip: 'Next track', icon: const Icon(Icons.skip_next), onPressed: () => onAction(const DeskAction.next())),
            ],
          ),
        if (volume != null)
          Row(
            children: [
              IconButton(tooltip: 'Volume down', icon: const Icon(Icons.volume_down), onPressed: () => onAction(const DeskAction.volumeDown())),
              Expanded(
                child: Semantics(
                  label: volume.muted ? 'Muted' : 'Volume ${volume.percent} percent',
                  child: ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (volume.percent / 100).clamp(0, 1).toDouble(),
                        minHeight: 6,
                        color: volume.muted ? colors.muted : colors.accent,
                        backgroundColor: colors.outline.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(tooltip: 'Volume up', icon: const Icon(Icons.volume_up), onPressed: () => onAction(const DeskAction.volumeUp())),
              IconButton(
                tooltip: volume.muted ? 'Unmute' : 'Mute',
                isSelected: volume.muted,
                icon: const Icon(Icons.volume_off_outlined),
                selectedIcon: Icon(Icons.volume_off, color: colors.danger),
                onPressed: () => onAction(const DeskAction.mute()),
              ),
            ],
          ),
      ],
    );
  }
}
