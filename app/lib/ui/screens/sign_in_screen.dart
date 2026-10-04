import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../app_scope.dart';
import '../widgets/surface.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = context.repo;
    try {
      if (_creating) {
        await repo.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
      } else {
        await repo.signIn(email: _email.text, password: _password.text);
      }
    } on LadderException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      // Shows in the console: non-network failures (e.g. a profile row that doesn't parse) land here too.
      debugPrint('Sign-in failed: $e\n$stack');
      if (mounted) {
        setState(
          () => _error = 'Couldn\'t reach the server. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final note = context.repo.modeNote;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Awake Coffee',
                        style: d.body(
                          16,
                          color: d.muted,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Chess, backgammon and SWU', style: d.display(46)),
                      const SizedBox(height: 12),
                      Text(
                        _creating
                            ? 'Make a profile. You\'ll start at 1000 in chess and Star Wars: Unlimited, 1500 in backgammon.'
                            : 'Sign in to log games and see where you stand.',
                        style: d.body(16, color: d.muted),
                      ),
                      const SizedBox(height: 28),
                      if (_creating) ...[
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            helperText:
                                'Shown on the ladder. You can change it later.',
                          ),
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.nickname],
                          validator: validateDisplayName,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter an email address'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        obscureText: true,
                        autofillHints: [
                          _creating
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Enter your password';
                          }
                          if (_creating && v.length < 8) {
                            return 'Use at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: d.body(
                            15,
                            color: d.loss,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_creating ? 'Create profile' : 'Sign in'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _creating = !_creating;
                                _error = null;
                              }),
                        child: Text(
                          _creating
                              ? 'I already have a profile'
                              : 'New here? Create a profile',
                        ),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 24),
                        SpecSurface(
                          padding: const EdgeInsets.all(14),
                          child: Text(note, style: d.body(14, color: d.muted)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
