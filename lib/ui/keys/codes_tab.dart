import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/otp_account.dart';
import '../../data/totp.dart';
import '../common/widgets.dart';
import 'code_editor_screen.dart';
import 'code_widgets.dart';
import 'page_width.dart';
import 'undo_toast.dart';

/// Authenticator codes: one row per account with the current code and a
/// ring counting down to the next one. Tap a row to copy its code.
class CodesTab extends StatelessWidget {
  const CodesTab({super.key, this.clock});

  final CodeClock? clock;

  static Future<void> add(BuildContext context) => CodeEditorScreen.open(context);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final accounts = [...store.otpAccounts]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        if (accounts.isEmpty) {
          return EmptyState(
            icon: Icons.pin_outlined,
            title: 'No codes yet',
            message: 'Add the one-time codes your servers or services ask for at login. '
                'Paste an otpauth:// setup link, or type the secret from the setup page.',
            actionLabel: 'Add code',
            onAction: () => add(context),
          );
        }
        return PageWidth(
          child: CodeTicker(
            clock: clock,
            builder: (context, now) => ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: PageLayout.fabClearance),
              itemCount: accounts.length,
              itemBuilder: (context, i) => CodeTile(key: ValueKey(accounts[i].id), account: accounts[i], now: now),
            ),
          ),
        );
      },
    );
  }
}

/// One account: name, linked host, the code (tap to copy) and the time left.
class CodeTile extends StatelessWidget {
  const CodeTile({super.key, required this.account, required this.now});

  final OtpAccount account;
  final DateTime now;

  Future<void> _delete(BuildContext context) async {
    final store = AppScope.store(context);
    final sure = await Confirm.ask(
      context,
      title: 'Delete ${account.title}?',
      message: 'Its codes stop showing here. If you still need them, keep the account in another authenticator first.',
      action: 'Delete',
    );
    if (!sure) return;
    store.deleteOtp(account.id);
    if (context.mounted) UndoToast.show(context, 'Deleted ${account.title}', () => store.saveOtp(account));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final text = Theme.of(context).textTheme;
    final code = currentCode(account, now);
    final host = AppScope.store(context).host(account.hostId);
    final details = [?account.subtitle, if (host != null) 'For ${host.title}'].join(' · ');
    return ListTile(
        minVerticalPadding: 10,
        onTap: code == null ? null : () => Toast.copy(context, code, what: 'Code copied'),
        title: Text(account.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty) Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: colors.muted)),
            const SizedBox(height: 4),
            code == null ? Text('This secret cannot be read', style: TextStyle(color: colors.danger)) : CodeText(code, style: text.headlineSmall?.copyWith(color: colors.accent)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CountdownRing(secondsLeft: Totp.secondsLeft(now, account.period), period: account.period),
            PopupMenuButton<String>(
              tooltip: 'More for ${account.title}',
              onSelected: (choice) => choice == 'edit' ? CodeEditorScreen.open(context, account: account) : _delete(context),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
    );
  }
}
