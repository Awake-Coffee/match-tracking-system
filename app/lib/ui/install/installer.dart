import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'installer_stub.dart'
    if (dart.library.js_interop) 'installer_web.dart'
    as platform;

/// How this browser can put the app on the home screen.
enum InstallRoute {
  /// Already installed, or the browser offers no way to (a desktop browser
  /// without install support, or an in-app browser).
  none,

  /// The browser's own install dialog, opened from a button.
  prompt,

  /// iOS Safari has no dialog to open: the member taps Share, then Add to
  /// Home Screen.
  shareSheet,
}

/// Puts the app on the member's home screen, where the browser allows it.
/// Notifies when [route] changes: the browser says it can install, or the
/// app was just installed.
abstract class Installer extends ChangeNotifier {
  Installer();

  /// The browser's installer on the web; one that never offers elsewhere.
  factory Installer.platform() => platform.createInstaller();

  InstallRoute get route;

  /// Opens the browser's install dialog; true when the member accepts it.
  Future<bool> install();
}

/// An installer with nothing to offer.
class NoInstaller extends Installer {
  @override
  InstallRoute get route => InstallRoute.none;

  @override
  Future<bool> install() async => false;
}

/// Provides the [Installer] and rebuilds dependents when its route changes.
class InstallScope extends InheritedNotifier<Installer> {
  const InstallScope({
    super.key,
    required Installer installer,
    required super.child,
  }) : super(notifier: installer);

  static Installer of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InstallScope>()?.notifier ??
      _none;

  static final _none = NoInstaller();
}

/// When the member last said "not now" to the install banner, in this
/// browser. The banner stays away for [quiet] after that. Storage failures
/// read as never snoozed and are otherwise ignored: the offer is a nicety.
abstract final class InstallOffer {
  static const _key = 'install_offer.snoozed_at';
  static const quiet = Duration(days: 30);

  static Future<bool> snoozed({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_key);
      if (at == null) return false;
      final since = (now ?? DateTime.now()).difference(
        DateTime.fromMillisecondsSinceEpoch(at),
      );
      return since < quiet;
    } catch (_) {
      return false;
    }
  }

  static Future<void> snooze({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, (now ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (_) {
      // Forgetting means the banner comes back; harmless.
    }
  }
}
