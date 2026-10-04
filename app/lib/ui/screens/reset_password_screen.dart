import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import '../app_scope.dart';
import '../widgets/password_field.dart';

/// Where the emailed reset link lands. The link has signed the member in; the
/// router keeps them here until they save a new password, which then ends
/// the recovery and sends them on to the ladder.
class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final repo = context.repo;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Awake Coffee',
                    style: d.body(16, color: d.muted, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Choose a new password', style: d.display(46)),
                  const SizedBox(height: 12),
                  Text(
                    'Pick something you haven\'t used before. '
                    'You\'ll be signed in right after.',
                    style: d.body(16, color: d.muted),
                  ),
                  const SizedBox(height: 28),
                  NewPasswordForm(
                    submitLabel: 'Save password',
                    onSubmit: repo.updatePassword,
                  ),
                  const SizedBox(height: 8),
                  // A way out for someone who opened the link by mistake.
                  TextButton(
                    onPressed: repo.signOut,
                    child: const Text('Cancel and sign out'),
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
