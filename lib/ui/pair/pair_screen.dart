import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_motion.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import '../../sessions/error_text.dart';
import '../../sessions/pairing_flow.dart';
import '../common/widgets.dart';
import '../hosts/host_connector.dart';
import '../settings/settings_widgets.dart';

/// Pair a computer: scan the QR code that `multiplex pair` shows on it.
/// Nothing is typed; the code carries the addresses, the user and the keys.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, this.flow});

  /// Tests pass a stand-in.
  final PairingFlow? flow;

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairScreen()));

  @override
  State<PairScreen> createState() => _PairScreenState();
}

enum _Stage { ready, pairing, done }

class _PairScreenState extends State<PairScreen> {
  late final PairingFlow _flow = widget.flow ?? PairingFlow(AppScope.store(context));
  final _code = TextEditingController();
  _Stage _stage = _Stage.ready;
  String? _error;
  String _name = '';
  Host? _paired;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _error = null);
    String? code;
    try {
      code = await _flow.scan();
    } on PlatformException catch (e) {
      setState(() => _error = 'The scanner could not open (${e.message ?? 'it needs Google Play services'}). Paste the code instead.');
      return;
    } on MissingPluginException {
      setState(() => _error = 'Scanning is not available here. Paste the code instead.');
      return;
    }
    if (code != null && mounted) await _pair(code);
  }

  Future<void> _pair(String code) async {
    final String name;
    try {
      name = _flow.read(code).name;
    } catch (e) {
      setState(() => _error = _sentence(e));
      return;
    }
    setState(() {
      _stage = _Stage.pairing;
      _name = name;
      _error = null;
    });
    try {
      final host = await _flow.pair(code);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _stage = _Stage.done;
        _paired = host;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.ready;
        _error = _sentence(e);
      });
    }
  }

  static String _sentence(Object e) => errorSentence(e, fallback: 'Pairing failed.');

  Future<void> _openDesktop() async {
    final host = _paired!;
    final navigator = Navigator.of(context);
    await HostConnector.openDesktop(context, host);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pair a computer')),
      body: ContentWidth(
        child: AnimatedSwitcher(
          duration: motion.page ~/ 2,
          switchInCurve: Curves.easeOutCubic,
          child: switch (_stage) {
            _Stage.ready => _Ready(key: const ValueKey('ready'), code: _code, error: _error, onScan: _scan, onPaste: () => _pair(_code.text)),
            _Stage.pairing => _Working(key: const ValueKey('pairing'), name: _name),
            _Stage.done => _Done(key: const ValueKey('done'), host: _paired!, onDesktop: _openDesktop, onDone: () => Navigator.of(context).pop()),
          },
        ),
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({super.key, required this.code, required this.error, required this.onScan, required this.onPaste});

  final TextEditingController code;
  final String? error;
  final VoidCallback onScan;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(SettingsLayout.gutter),
      children: [
        const SizedBox(height: 16),
        Icon(Icons.qr_code_scanner, size: 56, color: colors.accent),
        const SizedBox(height: 16),
        Text('Scan the code on your computer', style: text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'On the computer, open a terminal and run',
          style: text.bodyMedium?.copyWith(color: colors.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Center(child: MonoText('multiplex pair')),
        const SizedBox(height: 6),
        Text(
          'It shows a QR code. Scanning it sets everything up: no address, password or key to type.',
          style: text.bodyMedium?.copyWith(color: colors.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan the code')),
        if (error != null) ...[const SizedBox(height: 16), NoticeBox(tone: NoticeTone.error, text: error!)],
        const SizedBox(height: 28),
        const SectionHeader('No camera?'),
        TextField(
          controller: code,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(fontFamily: 'JetBrainsMonoNerd', fontSize: 13),
          decoration: const InputDecoration(labelText: 'Pairing code', hintText: 'MPX1.…', helperText: 'The line of text shown under the QR code'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ListenableBuilder(
            listenable: code,
            builder: (context, _) => FilledButton.tonal(onPressed: code.text.trim().isEmpty ? null : onPaste, child: const Text('Pair with this code')),
          ),
        ),
        const SizedBox(height: 16),
        const HelpText(
          'The phone has to reach the computer while pairing: be on the same Wi-Fi, or sign in to Tailscale '
          '(Settings, Tailscale) with the account the computer uses.',
        ),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(dimension: 32, child: CircularProgressIndicator(strokeWidth: 3, color: colors.accent)),
          const SizedBox(height: 20),
          Semantics(liveRegion: true, child: Text('Pairing with $name…', style: Theme.of(context).textTheme.titleMedium)),
        ],
      ),
    );
  }
}

/// The pairing-success moment: a check that grows in, then what to do next.
class _Done extends StatelessWidget {
  const _Done({super.key, required this.host, required this.onDesktop, required this.onDone});

  final Host host;
  final VoidCallback onDesktop;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final motion = AppMotion.of(context);
    final routes = [
      if (!host.viaTailscale) 'on your home network',
      if (host.viaTailscale || (host.tailscaleName ?? '').isNotEmpty) 'from anywhere over Tailscale',
    ].join(' and ');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: motion.page,
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0, 1),
                child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
              ),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.live.withValues(alpha: 0.16)),
                child: Icon(Icons.check_rounded, size: 52, color: colors.live),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: Text('Paired with ${host.title}', style: text.titleLarge, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            Text(
              'This phone can now reach it $routes.',
              style: text.bodyMedium?.copyWith(color: colors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(onPressed: onDesktop, icon: const Icon(Icons.desktop_windows_outlined), label: const Text('Open the desktop')),
            const SizedBox(height: 8),
            TextButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
