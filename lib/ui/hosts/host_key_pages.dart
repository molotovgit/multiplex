import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../src/rust/api/ssh_types.dart';
import '../common/widgets.dart';
import '../keys/page_width.dart';
import 'host_key_parts.dart';

/// Opens the server identity pages as full screens over the whole app.
abstract final class HostKeyPages {
  /// First visit: shows the fingerprint and asks to trust it. True = trust.
  static Future<bool> trustNew(BuildContext context, String host, int port, HostKeyInfo offered) => _open(
        context,
        NewHostKeyScreen(host: host, port: port, offered: offered),
      );

  /// The key is not the one trusted before. True = trust the new key.
  static Future<bool> acceptChanged(BuildContext context, String host, int port, HostKeyInfo offered, KnownHost? previous) => _open(
        context,
        ChangedHostKeyScreen(host: host, port: port, offered: offered, previous: previous),
      );

  static Future<bool> _open(BuildContext context, Widget page) async {
    if (!context.mounted) return false;
    final answer = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => page),
    );
    return answer ?? false;
  }
}

/// The first connection to a server: its fingerprint, shown clearly, and
/// how to check it before trusting it.
class NewHostKeyScreen extends StatelessWidget {
  const NewHostKeyScreen({super.key, required this.host, required this.port, required this.offered});

  final String host;
  final int port;
  final HostKeyInfo offered;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final address = HostKeyWords.address(host, port);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New server'),
        leading: IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
      ),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            HostKeyHeading(
              icon: Icons.fingerprint,
              color: colors.accent,
              title: 'First connection to $address',
              message: 'Multiplex has not seen this server before, so it cannot tell yet whether it is the real one. '
                  'Its fingerprint is below. Once you trust it, Multiplex warns you if it ever changes.',
            ),
            const SectionHeader('Server fingerprint'),
            FingerprintCard(label: 'Offered now', algorithm: offered.algorithm, fingerprint: offered.fingerprint),
            const SectionHeader('How to check it'),
            HostKeyCheckSteps(algorithm: offered.algorithm),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        action: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Trust and connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved server now shows a different key. Explains what changed, what
/// it can mean and how to check, and makes leaving the easy choice:
/// Disconnect is the big button, while trusting the new key needs the
/// server's name typed in, or a long press.
class ChangedHostKeyScreen extends StatefulWidget {
  const ChangedHostKeyScreen({super.key, required this.host, required this.port, required this.offered, this.previous, this.now});

  final String host;
  final int port;
  final HostKeyInfo offered;
  final KnownHost? previous;

  /// The clock, for "trusted 5 months ago"; tests pass a fixed one.
  final DateTime Function()? now;

  @override
  State<ChangedHostKeyScreen> createState() => _ChangedHostKeyScreenState();
}

class _ChangedHostKeyScreenState extends State<ChangedHostKeyScreen> {
  final _typed = TextEditingController();

  /// Set when "Trust the new key" was tapped before the name was typed.
  bool _needsName = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _nameMatches => _typed.text.trim().toLowerCase() == widget.host.toLowerCase();

  void _trust({bool held = false}) {
    if (held || _nameMatches) {
      Navigator.pop(context, true);
    } else {
      setState(() => _needsName = true);
    }
  }

  String? _trustedSince(BuildContext context) {
    final previous = widget.previous;
    if (previous == null) return null;
    final date = MaterialLocalizations.of(context).formatMediumDate(previous.addedAt);
    return 'Trusted since $date (${HostKeyWords.age(previous.addedAt, (widget.now ?? DateTime.now)())})';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final previous = widget.previous;
    final address = HostKeyWords.address(widget.host, widget.port);
    final typeChanged = previous != null && previous.algorithm != widget.offered.algorithm;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server identity changed'),
        leading: IconButton(tooltip: 'Disconnect', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
      ),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            HostKeyHeading(
              icon: Icons.gpp_bad_outlined,
              color: colors.danger,
              title: '$address is not showing the key you trusted',
              message: 'Multiplex stopped before sending your password or key. Do not continue until you know why the key changed.',
            ),
            const SectionHeader('What changed'),
            if (previous != null)
              FingerprintCard(label: 'Trusted before', algorithm: previous.algorithm, fingerprint: previous.fingerprint, footnote: _trustedSince(context)),
            FingerprintCard(
              label: 'Offered now',
              algorithm: widget.offered.algorithm,
              fingerprint: widget.offered.fingerprint,
              footnote: typeChanged ? 'The type of key changed too.' : null,
              danger: true,
            ),
            const SectionHeader('What it can mean'),
            ExplainRow(
              icon: Icons.build_outlined,
              title: 'Often harmless',
              text: 'The server was reinstalled, moved to a new machine, or its admin replaced the keys.',
              color: colors.muted,
            ),
            ExplainRow(
              icon: Icons.warning_amber_rounded,
              title: 'Sometimes an attack',
              text: 'Someone between this phone and the server is pretending to be it, to read your password and everything you type. '
                  'This is more likely on public or shared Wi-Fi.',
              color: colors.danger,
            ),
            const SectionHeader('What to check'),
            HostKeyCheckSteps(algorithm: widget.offered.algorithm),
            const SectionHeader('Trust the new key'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Only if you checked the new fingerprint. Type the server name to unlock the button, or press and hold it.',
                  style: text.bodyMedium?.copyWith(color: colors.muted)),
            ),
            FormRow(
              child: TextField(
                controller: _typed,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _needsName = false),
                decoration: InputDecoration(
                  labelText: 'Type ${widget.host}',
                  errorText: _needsName ? 'Type ${widget.host} first, or press and hold the button' : null,
                ),
              ),
            ),
            FormRow(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: colors.danger,
                  side: BorderSide(color: colors.danger),
                ),
                onPressed: _trust,
                onLongPress: () => _trust(held: true),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Trust the new key'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        action: FilledButton.icon(
          autofocus: true,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.pop(context, false),
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
        ),
      ),
    );
  }
}
