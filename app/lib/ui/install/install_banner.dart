import 'package:flutter/material.dart';

import '../../design/design_scope.dart';
import 'installer.dart';

/// What to tell a member about putting the app on their home screen, for
/// [route]; null when there is nothing to offer.
String? installHint(InstallRoute route) => switch (route) {
  InstallRoute.none => null,
  InstallRoute.prompt => 'It opens full screen, like any other app.',
  InstallRoute.shareSheet => 'In Safari, tap Share, then Add to Home Screen.',
};

/// Offers to put the app on the home screen, on phones, until the member
/// installs it or says not now (then it waits [InstallOffer.quiet]).
/// Nothing at all where the browser can't install or already has.
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  /// Until the snooze is read, stay hidden rather than flash the offer.
  bool _snoozed = true;

  @override
  void initState() {
    super.initState();
    InstallOffer.snoozed().then((snoozed) {
      if (mounted) setState(() => _snoozed = snoozed);
    });
  }

  void _notNow() {
    setState(() => _snoozed = true);
    InstallOffer.snooze();
  }

  Future<void> _install(Installer installer) async {
    final accepted = await installer.install();
    // Declining the browser's dialog is a "not now" too.
    if (!accepted && mounted) _notNow();
  }

  @override
  Widget build(BuildContext context) {
    final installer = InstallScope.of(context);
    final route = installer.route;
    final hint = installHint(route);
    if (_snoozed || hint == null) return const SizedBox.shrink();
    final d = context.design;
    return Semantics(
      container: true,
      label: 'Install the app',
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: d.surface,
          borderRadius: d.borderRadius,
          border: Border.all(color: d.line, width: d.lineWidth),
        ),
        child: Row(
          children: [
            Icon(Icons.install_mobile, color: d.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Keep the ladder on your phone', style: d.strong(15)),
                  Text(hint, style: d.body(13, color: d.muted)),
                ],
              ),
            ),
            if (route == InstallRoute.prompt) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _install(installer),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Install'),
              ),
            ],
            IconButton(
              tooltip: 'Not now',
              onPressed: _notNow,
              icon: Icon(Icons.close, color: d.muted),
            ),
          ],
        ),
      ),
    );
  }
}
