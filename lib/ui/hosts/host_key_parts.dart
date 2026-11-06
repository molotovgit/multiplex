import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme_look.dart';
import '../common/widgets.dart';
import '../keys/key_labels.dart';

/// Words and helpers shared by the two server identity pages.
abstract final class HostKeyWords {
  /// "host", or "host:port" when the port is not 22. IPv6 addresses get
  /// brackets so the port stands out.
  static String address(String host, int port) {
    if (port == 22) return host;
    return host.contains(':') ? '[$host]:$port' : '$host:$port';
  }

  /// The file that holds this type of key on a typical Linux server.
  static String serverFile(String algorithm) {
    final kind = switch (algorithm) {
      'ssh-ed25519' => 'ed25519',
      'ssh-rsa' || 'rsa-sha2-256' || 'rsa-sha2-512' => 'rsa',
      _ when algorithm.startsWith('ecdsa-') => 'ecdsa',
      _ => 'ed25519',
    };
    return '/etc/ssh/ssh_host_${kind}_key.pub';
  }

  /// The command that prints the server's own fingerprint.
  static String checkCommand(String algorithm) => 'ssh-keygen -lf ${serverFile(algorithm)}';

  /// "today", "3 days ago", "5 months ago", "2 years ago".
  static String age(DateTime since, DateTime now) {
    final days = now.difference(since).inDays;
    if (days < 1) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 60) return '$days days ago';
    final months = days ~/ 30;
    if (months < 24) return '$months months ago';
    return '${days ~/ 365} years ago';
  }
}

/// One server key: its type and fingerprint, large and selectable, with a
/// copy button, and an optional line under it (such as when it was trusted).
class FingerprintCard extends StatelessWidget {
  const FingerprintCard({super.key, required this.label, required this.algorithm, required this.fingerprint, this.footnote, this.danger = false});

  final String label;
  final String algorithm;
  final String fingerprint;
  final String? footnote;

  /// Draws the edge in the warning colour (the key that is offered now,
  /// after a change).
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: danger ? RoundedRectangleBorder(side: BorderSide(color: colors.danger, width: 1.5), borderRadius: BorderRadius.circular(AppStyleTheme.of(context).shapes.card)) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label · ${KeyAlgorithms.label(algorithm)}', style: text.labelLarge?.copyWith(color: danger ? colors.danger : colors.muted)),
                  const SizedBox(height: 6),
                  MonoText(fingerprint, selectable: true, style: text.titleSmall),
                  if (footnote != null) ...[
                    const SizedBox(height: 6),
                    Text(footnote!, style: text.bodySmall?.copyWith(color: colors.muted)),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy fingerprint',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => Toast.copy(context, fingerprint, what: 'Fingerprint copied'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered or bulleted line of explanation with an icon.
class ExplainRow extends StatelessWidget {
  const ExplainRow({super.key, required this.icon, required this.title, required this.text, this.color});

  final IconData icon;
  final String title;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final style = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? colors.muted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: style.titleSmall),
                const SizedBox(height: 2),
                Text(text, style: style.bodyMedium?.copyWith(color: colors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How to make sure a fingerprint is the real one: ask the admin, or read
/// it on the server's own screen.
class HostKeyCheckSteps extends StatelessWidget {
  const HostKeyCheckSteps({super.key, required this.algorithm});

  final String algorithm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final command = HostKeyWords.checkCommand(algorithm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExplainRow(
          icon: Icons.forum_outlined,
          title: 'Ask the admin',
          text: 'Ask whoever runs the server whether it was reinstalled or its keys were changed, and what the new fingerprint is.',
        ),
        const ExplainRow(
          icon: Icons.terminal,
          title: 'Or look on the server itself',
          text: 'On the server\'s own console (not over SSH from this phone), run this command and compare the result with the fingerprint above:',
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(50, 4, 16, 8),
          color: colors.raised,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Expanded(child: MonoText(command, selectable: true)),
                IconButton(
                  tooltip: 'Copy command',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () => Toast.copy(context, command, what: 'Command copied'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Big icon, title and one line under it, at the top of the page.
class HostKeyHeading extends StatelessWidget {
  const HostKeyHeading({super.key, required this.icon, required this.color, required this.title, required this.message});

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColorsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(title, style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(message, style: text.bodyLarge?.copyWith(color: colors.muted)),
        ],
      ),
    );
  }
}
