import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../common/widgets.dart';

/// Name, address, port and user name.
class ServerFields extends StatelessWidget {
  const ServerFields({super.key, required this.label, required this.address, required this.port, required this.user});

  final TextEditingController label;
  final TextEditingController address;
  final TextEditingController port;
  final TextEditingController user;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: address,
          autofocus: address.text.isEmpty,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Address', hintText: 'server.example.com or 203.0.113.10'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the server address' : null,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: user,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'User name', hintText: 'root'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a user name' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 1 || n > 65535 ? '1 to 65535' : null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: label,
          decoration: const InputDecoration(
            labelText: 'Name (optional)',
            hintText: 'Web server',
            helperText: 'Shown in the list instead of the address',
          ),
        ),
      ],
    );
  }
}

/// How to log in: password, key, or both.
class LoginFields extends StatefulWidget {
  const LoginFields({
    super.key,
    required this.mode,
    required this.onMode,
    required this.password,
    required this.keys,
    required this.keyId,
    required this.keyError,
    required this.onKey,
    required this.onNewKey,
  });

  final AuthMode mode;
  final ValueChanged<AuthMode> onMode;
  final TextEditingController password;
  final List<StoredKey> keys;
  final String? keyId;
  final bool keyError;
  final ValueChanged<String?> onKey;
  final VoidCallback onNewKey;

  @override
  State<LoginFields> createState() => _LoginFieldsState();
}

class _LoginFieldsState extends State<LoginFields> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final showKey = widget.mode != AuthMode.password;
    final showPassword = widget.mode != AuthMode.key;
    final selected = widget.keys.any((k) => k.id == widget.keyId) ? widget.keyId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<AuthMode>(
          segments: const [
            ButtonSegment(value: AuthMode.password, icon: Icon(Icons.password), label: Text('Password')),
            ButtonSegment(value: AuthMode.key, icon: Icon(Icons.key), label: Text('Key')),
            ButtonSegment(value: AuthMode.keyAndPassword, label: Text('Both')),
          ],
          selected: {widget.mode},
          onSelectionChanged: (s) => widget.onMode(s.first),
        ),
        if (showKey) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Key',
                    errorText: widget.keyError ? 'Choose a key or create one' : null,
                    helperText: widget.keys.isEmpty ? 'No keys yet: create one with the button' : null,
                  ),
                  items: [
                    for (final key in widget.keys)
                      DropdownMenuItem(
                        value: key.id,
                        child: Text('${key.name}  ·  ${key.algorithm}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: widget.onKey,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IconButton.filledTonal(tooltip: 'Create or import a key', onPressed: widget.onNewKey, icon: const Icon(Icons.add)),
              ),
            ],
          ),
        ],
        if (showPassword) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.password,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'Leave empty to be asked each time',
              helperStyle: TextStyle(color: colors.muted),
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Group and tag colour.
class OrganiseFields extends StatelessWidget {
  const OrganiseFields({
    super.key,
    required this.groups,
    required this.groupId,
    required this.onGroup,
    required this.onNewGroup,
    required this.tag,
    required this.onTag,
  });

  final List<HostGroup> groups;
  final String? groupId;
  final ValueChanged<String?> onGroup;
  final VoidCallback onNewGroup;
  final int tag;
  final ValueChanged<int> onTag;

  @override
  Widget build(BuildContext context) {
    final selected = groups.any((g) => g.id == groupId) ? groupId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No group')),
                  for (final g in groups) DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
                ],
                onChanged: onGroup,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'New group', onPressed: onNewGroup, icon: const Icon(Icons.create_new_folder_outlined)),
          ],
        ),
        const SizedBox(height: 16),
        Text('Colour', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (var i = 0; i < TagColors.values.length; i++) _TagChoice(index: i, selected: i == tag, onTap: () => onTag(i))],
        ),
      ],
    );
  }
}

class _TagChoice extends StatelessWidget {
  const _TagChoice({required this.index, required this.selected, required this.onTap});

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final color = index == 0 ? colors.raised : TagColors.of(index);
    return Semantics(
      button: true,
      selected: selected,
      label: index == 0 ? 'No colour' : 'Colour ${index + 1}',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? colors.text : colors.outline, width: selected ? 3 : 1),
          ),
          child: index == 0
              ? Icon(Icons.block, size: 18, color: colors.muted)
              : (selected ? const Icon(Icons.check, size: 20, color: Colors.white) : null),
        ),
      ),
    );
  }
}

/// Jump host, tmux and startup command.
class AdvancedFields extends StatelessWidget {
  const AdvancedFields({
    super.key,
    required this.jumpHosts,
    required this.jumpId,
    required this.onJump,
    required this.startup,
    required this.tmux,
    required this.onTmux,
  });

  final List<Host> jumpHosts;
  final String? jumpId;
  final ValueChanged<String?> onJump;
  final TextEditingController startup;
  final bool tmux;
  final ValueChanged<bool> onTmux;

  @override
  Widget build(BuildContext context) {
    final selected = jumpHosts.any((h) => h.id == jumpId) ? jumpId : null;
    return Column(
      children: [
        DropdownButtonFormField<String?>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Jump host', helperText: 'Connect through another saved host first, like ssh -J'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('None: connect directly')),
            for (final h in jumpHosts) DropdownMenuItem<String?>(value: h.id, child: Text(h.title)),
          ],
          onChanged: onJump,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Keep session with tmux'),
          subtitle: const Text('Each terminal runs in tmux on the server, so after a reconnect you are back on the same screen'),
          value: tmux,
          onChanged: onTmux,
        ),
        if (!tmux)
          TextFormField(
            controller: startup,
            autocorrect: false,
            style: const TextStyle(fontFamily: 'JetBrainsMonoNerd'),
            decoration: const InputDecoration(
              labelText: 'Startup command (optional)',
              hintText: 'cd /var/www',
              helperText: 'Typed for you after login',
            ),
          ),
      ],
    );
  }
}
