import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models.dart';
import '../../data/vault_store.dart';
import '../common/widgets.dart';
import '../keys/keychain_screen.dart';
import 'host_form_fields.dart';
import 'hosts_screen.dart';

/// Adds a new host or edits a saved one.
class HostEditorScreen extends StatefulWidget {
  const HostEditorScreen({super.key, this.host, this.initialGroupId});

  final Host? host;
  final String? initialGroupId;

  @override
  State<HostEditorScreen> createState() => _HostEditorScreenState();
}

class _HostEditorScreenState extends State<HostEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final Host _original = widget.host ?? Host(id: VaultStore.newId(), label: '', address: '', groupId: widget.initialGroupId);

  late final _label = TextEditingController(text: _original.label);
  late final _address = TextEditingController(text: _original.address);
  late final _port = TextEditingController(text: '${_original.port}');
  late final _user = TextEditingController(text: _original.username);
  late final _password = TextEditingController(text: _original.password ?? '');
  late final _startup = TextEditingController(text: _original.startupCommand ?? '');

  late AuthMode _auth = _original.authMode;
  late String? _keyId = _original.keyId;
  late String? _groupId = _original.groupId;
  late String? _jumpId = _original.jumpHostId;
  late int _tag = _original.colorTag;
  bool _keyError = false;

  bool get _isNew => widget.host == null;

  @override
  void dispose() {
    for (final c in [_label, _address, _port, _user, _password, _startup]) {
      c.dispose();
    }
    super.dispose();
  }

  Host _current() => _original.copyWith(
    label: _label.text.trim(),
    address: _address.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 22,
    username: _user.text.trim(),
    authMode: _auth,
    password: () => _auth == AuthMode.key || _password.text.isEmpty ? null : _password.text,
    keyId: () => _auth == AuthMode.password ? null : _keyId,
    groupId: () => _groupId,
    jumpHostId: () => _jumpId,
    startupCommand: () => _startup.text.trim().isEmpty ? null : _startup.text.trim(),
    colorTag: _tag,
  );

  bool get _changed => _current().toJson().toString() != _original.toJson().toString();

  void _save() {
    final needsKey = _auth != AuthMode.password && AppScope.store(context).key(_keyId) == null;
    setState(() => _keyError = needsKey);
    if (!_form.currentState!.validate() || needsKey) return;
    AppScope.store(context).saveHost(_current());
    Toast.show(context, _isNew ? 'Saved ${_current().title}' : 'Changes saved');
    Navigator.of(context).pop();
  }

  Future<void> _newKey() async {
    final key = await KeyCreator.open(context);
    if (key != null && mounted) {
      setState(() {
        _keyId = key.id;
        _keyError = false;
      });
    }
  }

  Future<void> _newGroup() async {
    final name = await GroupNameDialog.ask(context);
    if (name == null || !mounted) return;
    final group = HostGroup(id: VaultStore.newId(), name: name);
    AppScope.store(context).saveGroup(group);
    setState(() => _groupId = group.id);
  }

  Future<bool> _confirmDiscard() async {
    if (!_changed) return true;
    return Confirm.ask(context, title: 'Discard changes?', message: 'Your changes to this host are not saved.', action: 'Discard');
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.store(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New host' : 'Edit host'),
          actions: [TextButton(onPressed: _save, child: const Text('Save'))],
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) => Form(
            key: _form,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    const SectionHeader('Server'),
                    ServerFields(label: _label, address: _address, port: _port, user: _user),
                    const SectionHeader('Login'),
                    LoginFields(
                      mode: _auth,
                      onMode: (m) => setState(() => _auth = m),
                      password: _password,
                      keys: store.keys,
                      keyId: _keyId,
                      keyError: _keyError,
                      onKey: (id) => setState(() {
                        _keyId = id;
                        _keyError = false;
                      }),
                      onNewKey: _newKey,
                    ),
                    const SectionHeader('Organise'),
                    OrganiseFields(
                      groups: store.groups,
                      groupId: _groupId,
                      onGroup: (id) => setState(() => _groupId = id),
                      onNewGroup: _newGroup,
                      tag: _tag,
                      onTag: (t) => setState(() => _tag = t),
                    ),
                    const SectionHeader('Advanced'),
                    AdvancedFields(
                      jumpHosts: store.hosts.where((h) => h.id != _original.id && h.jumpHostId != _original.id).toList(),
                      jumpId: _jumpId,
                      onJump: (id) => setState(() => _jumpId = id),
                      startup: _startup,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: _save, child: Text(_isNew ? 'Save host' : 'Save changes')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
