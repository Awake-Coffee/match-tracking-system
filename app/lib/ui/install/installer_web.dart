import 'dart:js_interop';

import 'installer.dart';

/// `window.awakeInstall`, set up in web/index.html before Flutter loads so
/// it catches the browser's install event however early that fires.
@JS('awakeInstall')
external _Bridge? get _bridge;

extension type _Bridge._(JSObject _) implements JSObject {
  /// Running from the home screen already.
  external bool standalone();

  /// The browser has offered its install dialog and it is still unused.
  external bool canPrompt();

  /// iPhone or iPad, where Safari installs only from the Share sheet.
  external bool ios();

  /// Opens the install dialog; resolves to "accepted" or "dismissed".
  external JSPromise<JSString> prompt();

  /// Calls [callback] whenever what the bridge reports changes.
  external void listen(JSFunction callback);
}

Installer createInstaller() => _WebInstaller();

class _WebInstaller extends Installer {
  _WebInstaller() {
    _bridge?.listen(notifyListeners.toJS);
  }

  @override
  InstallRoute get route {
    final bridge = _bridge;
    if (bridge == null || bridge.standalone()) return InstallRoute.none;
    if (bridge.canPrompt()) return InstallRoute.prompt;
    if (bridge.ios()) return InstallRoute.shareSheet;
    return InstallRoute.none;
  }

  @override
  Future<bool> install() async {
    final bridge = _bridge;
    if (bridge == null) return false;
    final outcome = await bridge.prompt().toDart;
    return outcome.toDart == 'accepted';
  }
}
