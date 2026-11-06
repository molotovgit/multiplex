import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/otp_account.dart';
import '../../data/totp.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import 'mono_style.dart';
import 'page_width.dart';

/// Adds a one-time code account, or edits one. The quickest way in is to
/// paste the otpauth:// setup link (the text inside the setup QR code);
/// the fields can also be typed from the service's setup page.
class CodeEditorScreen extends StatefulWidget {
  const CodeEditorScreen({super.key, this.account});

  final OtpAccount? account;

  static Future<void> open(BuildContext context, {OtpAccount? account}) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => CodeEditorScreen(account: account)),
      );

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _link = TextEditingController();
  late final _issuer = TextEditingController(text: widget.account?.issuer ?? '');
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _secret = TextEditingController(text: widget.account?.secret ?? '');
  late OtpAlgorithm _algorithm = widget.account?.algorithm ?? OtpAlgorithm.sha1;
  late int _digits = widget.account?.digits ?? 6;
  late int _period = widget.account?.period ?? 30;
  late String? _hostId = widget.account?.hostId;
  bool _secretHidden = true;

  /// What happened with the pasted link: filled in, or why not.
  String? _linkNote;
  bool _linkFailed = false;

  bool get _isNew => widget.account == null;

  @override
  void dispose() {
    for (final c in [_link, _issuer, _name, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    _link.text = text;
    _readLink(text);
  }

  void _readLink(String text) {
    if (text.trim().isEmpty) {
      setState(() => _linkNote = null);
      return;
    }
    try {
      final link = OtpLink.parse(text);
      setState(() {
        _issuer.text = link.issuer;
        _name.text = link.name;
        _secret.text = link.secret;
        _algorithm = link.algorithm;
        _digits = link.digits;
        _period = link.period;
        _linkNote = 'Filled in from the link. Check the name, then save.';
        _linkFailed = false;
      });
    } on FormatException catch (e) {
      setState(() {
        _linkNote = e.message;
        _linkFailed = true;
      });
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final store = AppScope.store(context);
    final account = (widget.account ?? OtpAccount(id: VaultStore.newId(), secret: '', createdAt: DateTime.now())).copyWith(
      issuer: _issuer.text.trim(),
      name: _name.text.trim(),
      secret: Base32.normalize(_secret.text),
      algorithm: _algorithm,
      digits: _digits,
      period: _period,
      hostId: () => _hostId,
    );
    store.saveOtp(account);
    Toast.show(context, _isNew ? 'Added ${account.title}' : 'Changes saved');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final store = AppScope.store(context);
    final hosts = store.hosts;
    final hostId = hosts.any((h) => h.id == _hostId) ? _hostId : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add code' : 'Edit code'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: PageWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (_isNew) ...[
                const SectionHeader('Setup link'),
                FormRow(
                  child: TextField(
                    controller: _link,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: MonoStyle.of(context),
                    onChanged: _readLink,
                    decoration: InputDecoration(
                      labelText: 'otpauth:// link',
                      helperText: _linkFailed ? null : (_linkNote ?? 'The text inside the setup QR code. Many sites show it under "Can\'t scan?"'),
                      errorText: _linkFailed ? _linkNote : null,
                      helperMaxLines: 2,
                      suffixIcon: IconButton(tooltip: 'Paste link', icon: const Icon(Icons.content_paste), onPressed: _paste),
                    ),
                  ),
                ),
              ],
              const SectionHeader('Account'),
              FormRow(
                child: TextFormField(
                  controller: _issuer,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Service', hintText: 'GitHub, bastion, VPN'),
                ),
              ),
              FormRow(
                child: TextFormField(
                  controller: _name,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Account (optional)', hintText: 'alice@example.com'),
                ),
              ),
              FormRow(
                child: TextFormField(
                  controller: _secret,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: _secretHidden,
                  style: MonoStyle.of(context),
                  validator: (v) => Base32.isValid(v ?? '') ? null : 'Enter the secret: letters A to Z and digits 2 to 7',
                  decoration: InputDecoration(
                    labelText: 'Secret key',
                    helperText: 'Kept only in the encrypted vault on this phone',
                    suffixIcon: IconButton(
                      tooltip: _secretHidden ? 'Show secret' : 'Hide secret',
                      icon: Icon(_secretHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _secretHidden = !_secretHidden),
                    ),
                  ),
                ),
              ),
              const SectionHeader('Use at login'),
              FormRow(
                child: DropdownButtonFormField<String?>(
                  initialValue: hostId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Offer for host', helperText: 'When this host asks for a code, it is offered in one tap'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No host')),
                    for (final h in hosts) DropdownMenuItem<String?>(value: h.id, child: Text(h.title)),
                  ],
                  onChanged: (id) => setState(() => _hostId = id),
                ),
              ),
              const SectionHeader('Code format'),
              FormRow(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<int>(
                      segments: const [ButtonSegment(value: 6, label: Text('6 digits')), ButtonSegment(value: 8, label: Text('8 digits'))],
                      selected: {_digits},
                      onSelectionChanged: (v) => setState(() => _digits = v.first),
                    ),
                    SegmentedButton<int>(
                      segments: [for (final p in {30, 60, _period}) ButtonSegment(value: p, label: Text('$p s'))],
                      selected: {_period},
                      onSelectionChanged: (v) => setState(() => _period = v.first),
                    ),
                    DropdownButton<OtpAlgorithm>(
                      value: _algorithm,
                      items: [for (final a in OtpAlgorithm.values) DropdownMenuItem(value: a, child: Text(a.label))],
                      onChanged: (a) => setState(() => _algorithm = a ?? _algorithm),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Leave these as they are unless the setup page says otherwise.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted)),
              ),
              const SizedBox(height: 24),
              FormRow(child: FilledButton(onPressed: _save, child: Text(_isNew ? 'Add code' : 'Save changes'))),
            ],
          ),
        ),
      ),
    );
  }
}
