import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../app_scope.dart';
import '../widgets/password_field.dart';
import '../widgets/surface.dart';

const _rowHeight = 56.0;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: context.repo.me?.displayName);
  bool _savingName = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveName() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _savingName = true);
    try {
      await context.repo.updateDisplayName(_name.text);
      _toast('Name saved.');
    } on LadderException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  /// Signing out is one tap from the password form, so ask first.
  Future<void> _signOut() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Awake Ladder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await context.repo.signOut();
  }

  Future<void> _deleteAccount() async {
    final repo = context.repo;
    // Read once: the dialog is still on screen when the sign-out lands.
    final name = repo.me!.displayName;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteAccountDialog(name: name),
    );
    if (go != true || !mounted) return;
    try {
      // Signs out too, which takes this screen away.
      await repo.deleteAccount();
    } on LadderException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.repo;
    final d = context.design;
    final email = repo.email;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ScreenTitle(
          'Settings',
          subtitle: email == null ? null : 'Signed in as $email',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Form(
            key: _form,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _name,
                    // Fixed height so the field lines up with the button
                    // whatever the font metrics.
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      constraints: BoxConstraints.tightFor(height: _rowHeight),
                    ),
                    validator: validateDisplayName,
                    onFieldSubmitted: (_) => _saveName(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: _rowHeight,
                  child: FilledButton(
                    onPressed: _savingName ? null : _saveName,
                    child: const Text('Save name'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change password', style: d.display(22)),
              const SizedBox(height: 16),
              NewPasswordForm(
                submitLabel: 'Change password',
                onSubmit: (password) async {
                  await repo.updatePassword(password);
                  _toast('Password updated.');
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
          child: OutlinedButton(
            onPressed: _signOut,
            child: const Text('Sign out'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete account', style: d.display(22)),
              const SizedBox(height: 8),
              const Text(
                'Removes your profile, your ratings and any games still '
                'waiting for confirmation. Results already confirmed stay in '
                'the history under the name you played them as. This can\'t '
                'be undone.',
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: d.loss,
                  side: BorderSide(color: d.loss),
                ),
                onPressed: _deleteAccount,
                child: const Text('Delete account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Deleting can't be undone, so the member types their display name first.
/// Pops true once they confirm.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.name});

  final String name;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches => _typed.text.trim() == widget.name;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your profile and ratings are removed for good. Confirmed results '
            'stay in the history under the name ${widget.name}. Type '
            '${widget.name} to confirm.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Display name'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: d.loss),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
