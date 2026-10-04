/// Every page is a URL and every move between pages is `context.go`, so each
/// one is a browser history entry: Back and Forward work, and the address bar
/// is always a link to what is on screen. go_router's imperative `push` would
/// change the page without changing the address, so the app doesn't use it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

/// Leaves a page the member opened from another, as the browser's Back button
/// would, so the page they came from comes back as they left it.
///
/// When this page is the first the app showed (a shared link, a bookmark),
/// stepping back would leave the site, so it goes to [fallback] instead.
void goBack(BuildContext context, {required String fallback}) {
  final strategy = urlStrategy;
  if (strategy != null && _entryIndex(strategy.getState()) > 0) {
    strategy.go(-1);
  } else {
    context.go(fallback);
  }
}

/// Where the current browser history entry sits among the app's own, 0 for
/// the one it opened on. Flutter's web engine tags each entry it creates with
/// this count, and the tag survives a reload. An untagged entry counts as the
/// first, so a change in the tag only ever costs a trip to the fallback.
int _entryIndex(Object? state) => switch (state) {
  {'serialCount': final num count} => count.toInt(),
  _ => 0,
};

/// The route to return to after signing in, from the `from` query of the
/// sign-in page: a path within the app, or null.
String? returnPath(String? from) {
  if (from == null || !from.startsWith('/')) return null;
  // `//host` and `/\host` are other sites to a browser.
  if (from.startsWith('//') || from.startsWith(r'/\')) return null;
  return from;
}
