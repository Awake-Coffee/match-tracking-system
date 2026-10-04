import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../design/design_spec.dart';
import '../app_scope.dart';
import '../widgets/password_field.dart';
import '../widgets/surface.dart';

/// Headline size under the "Awake Coffee" eyebrow on the signed-out screens:
/// 34 rather than 46 so the spelled-out games name wraps to about the old
/// headline's height on a phone.
const authHeadlineSize = 34.0;

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

  /// Asking for a password-reset email instead of signing in.
  bool _resetting = false;
  bool _busy = false;
  String? _error;

  /// The address a confirmation email was sent to; set after a sign-up that
  /// needs the emailed link, and replaces the form until the member goes back.
  String? _confirming;

  /// The address a reset link was sent to; replaces the form like [_confirming].
  String? _resetSent;

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
    // Asking for a fresh link is moving on from the broken one.
    if (repo.authLinkError != null) {
      _resetting = true;
      repo.clearAuthLinkError();
    }
    try {
      if (_resetting) {
        await repo.sendPasswordReset(_email.text);
        if (mounted) setState(() => _resetSent = _email.text.trim());
      } else if (_creating) {
        final result = await repo.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
        if (result == SignUpResult.confirmationSent && mounted) {
          // The form is about to go; tell the browser it was submitted so it
          // offers to save the new password.
          TextInput.finishAutofillContext();
          setState(() => _confirming = _email.text.trim());
        }
      } else {
        await repo.signIn(email: _email.text, password: _password.text);
      }
    } on LadderException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      // Auth and database errors, including dropped connections, arrive as
      // LadderException. Anything else is usually a tab running an older build
      // than the database schema, which a reload fixes.
      debugPrint('Sign-in failed: $e\n$stack');
      if (mounted) {
        setState(
          () => _error = 'Something went wrong. Reload the page and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The intro, fields, error and buttons of the sign-in / sign-up form.
  List<Widget> _formFields(DesignSpec d) => [
    Text(
      _creating
          ? 'Report the games you play at the café. Your opponent confirms '
                'the result, and then both ratings move.'
          : 'Sign in to log your games and see where you stand on the '
                'café\'s ladders.',
      style: d.body(16, color: d.muted),
    ),
    const SizedBox(height: 28),
    if (_creating) ...[
      TextFormField(
        controller: _name,
        decoration: const InputDecoration(
          labelText: 'Display name',
          helperText: 'Shown on the ladder. You can change it later.',
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
      validator: (v) =>
          (v == null || !v.contains('@')) ? 'Enter an email address' : null,
    ),
    const SizedBox(height: 16),
    PasswordField(
      controller: _password,
      autofillHints: [
        _creating ? AutofillHints.newPassword : AutofillHints.password,
      ],
      onFieldSubmitted: (_) => _submit(),
      validator: (v) {
        if (v == null || v.isEmpty) {
          return 'Enter your password';
        }
        return _creating ? validateNewPassword(v) : null;
      },
    ),
    if (!_creating)
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _resetting = true;
                  _error = null;
                }),
          child: const Text('Forgot password?'),
        ),
      ),
    if (_error != null) ...[
      const SizedBox(height: 16),
      Text(
        _error!,
        style: d.body(15, color: d.loss, weight: FontWeight.w600),
      ),
    ],
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : _submit,
      child: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
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
        _creating ? 'I already have a profile' : 'New here? Create a profile',
      ),
    ),
  ];

  /// The email form that asks for a password-reset link. [linkError] says why
  /// the link the app was opened from didn't work; the member came for a new
  /// password, so the form is ready for the next request.
  List<Widget> _resetFields(DesignSpec d, String? linkError) => [
    Text(
      'Enter the email you signed up with and we\'ll send you a link to '
      'choose a new password.',
      style: d.body(16, color: d.muted),
    ),
    const SizedBox(height: 28),
    TextFormField(
      controller: _email,
      autofocus: linkError != null,
      decoration: const InputDecoration(labelText: 'Email'),
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.email],
      onFieldSubmitted: (_) => _submit(),
      validator: (v) =>
          (v == null || !v.contains('@')) ? 'Enter an email address' : null,
    ),
    if ((_error ?? linkError) case final error?) ...[
      const SizedBox(height: 16),
      Text(
        error,
        style: d.body(15, color: d.loss, weight: FontWeight.w600),
      ),
    ],
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : _submit,
      child: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Send reset link'),
    ),
    const SizedBox(height: 8),
    TextButton(
      onPressed: _busy ? null : _backToSignIn,
      child: const Text('Back to sign in'),
    ),
  ];

  /// Leaves the confirmation or reset panel for the sign-in form, email filled in.
  void _backToSignIn() {
    context.repo.clearAuthLinkError();
    setState(() {
      _email.text = _confirming ?? _resetSent ?? _email.text;
      _password.clear();
      _confirming = null;
      _resetSent = null;
      _resetting = false;
      _creating = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final note = context.repo.modeNote;
    final linkError = context.repo.authLinkError;
    final confirming = _confirming;
    final resetSent = _resetSent;
    return Scaffold(
      body: SpecBackdrop(
        child: SafeArea(
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
                          d.caps('Awake Coffee'),
                          style: d.display(14, color: d.muted),
                        ),
                        const SizedBox(height: 4),
                        // Spelled out for newcomers.
                        Text(
                          'Chess, backgammon and Star Wars: Unlimited',
                          style: d.display(authHeadlineSize),
                        ),
                        const SizedBox(height: 12),
                        if (confirming != null)
                          _ConfirmationPanel(
                            email: confirming,
                            onBack: _backToSignIn,
                          )
                        else if (resetSent != null)
                          _ResetSentPanel(
                            email: resetSent,
                            onBack: _backToSignIn,
                            onTryAgain: () => setState(() => _resetSent = null),
                          )
                        else if (_resetting || linkError != null)
                          ..._resetFields(d, linkError)
                        else
                          ..._formFields(d),
                        if (note != null) ...[
                          const SizedBox(height: 24),
                          SpecSurface(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              note,
                              style: d.body(14, color: d.muted),
                            ),
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
      ),
    );
  }
}

/// Confirms a password-reset email is on its way. A success, so it matches
/// [_ConfirmationPanel] rather than using the loss colour. It is shown for
/// any address, since the backend doesn't say whether an account exists.
class _ResetSentPanel extends StatelessWidget {
  const _ResetSentPanel({
    required this.email,
    required this.onBack,
    required this.onTryAgain,
  });

  final String email;
  final VoidCallback onBack;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.mark_email_read_outlined, color: d.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    // Replaces the focused form, so announce it to screen readers.
                    child: Semantics(
                      liveRegion: true,
                      child: Text('Check your inbox', style: d.display(24)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('We sent a link to', style: d.body(16)),
              const SizedBox(height: 2),
              Text(
                email,
                style: d.body(16, color: d.accent, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Open it on this device, in this browser, to choose a new '
                'password. It can take a minute, and may land in spam.',
                style: d.body(15, color: d.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onBack, child: const Text('Back to sign in')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onTryAgain,
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}

/// Tells a new member to open the emailed link, and lets them ask for it
/// again. A success, so it uses the surface and accent rather than the loss
/// colour that real errors get.
class _ConfirmationPanel extends StatefulWidget {
  const _ConfirmationPanel({required this.email, required this.onBack});

  final String email;
  final VoidCallback onBack;

  @override
  State<_ConfirmationPanel> createState() => _ConfirmationPanelState();
}

class _ConfirmationPanelState extends State<_ConfirmationPanel> {
  /// Supabase's default gap between auth emails to one address; the sign-up
  /// email counts, so the panel starts out waiting too.
  static const _cooldown = Duration(seconds: 60);

  Timer? _timer;
  bool _waiting = false;
  bool _sending = false;
  bool _sentAgain = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _wait();
  }

  /// Disables "Resend email" until the email service will take another.
  void _wait() {
    _waiting = true;
    _timer?.cancel();
    _timer = Timer(_cooldown, () {
      if (mounted) {
        setState(() {
          _waiting = false;
          _sentAgain = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.repo.resendSignUpConfirmation(widget.email);
      if (!mounted) return;
      setState(() {
        _sentAgain = true;
        _wait();
      });
    } on LadderException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      debugPrint('Resending confirmation failed: $e\n$stack');
      if (mounted) {
        setState(() => _error = 'Couldn\'t send the email. Try again shortly.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpecSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.mark_email_read_outlined, color: d.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    // Replaces the focused form, so announce it to screen readers.
                    child: Semantics(
                      liveRegion: true,
                      child: Text('Check your inbox', style: d.display(24)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('We sent a confirmation link to', style: d.body(16)),
              const SizedBox(height: 2),
              Text(
                widget.email,
                style: d.body(16, color: d.accent, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Open it to activate your profile, then sign in. '
                'It can take a minute, and may land in spam.',
                style: d.body(15, color: d.muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: d.body(15, color: d.loss, weight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.onBack,
          child: const Text('Back to sign in'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _sending || _waiting ? null : _resend,
          child: Text(
            _sending
                ? 'Sending…'
                : _sentAgain
                ? 'Sent again'
                : _waiting
                ? 'You can resend in a minute'
                : 'Resend email',
          ),
        ),
      ],
    );
  }
}
