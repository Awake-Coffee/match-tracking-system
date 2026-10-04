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
            onPressed: () => repo.signOut(),
            child: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}
