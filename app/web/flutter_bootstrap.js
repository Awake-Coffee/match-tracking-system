{{flutter_js}}
{{flutter_build_config}}
// No serviceWorkerSettings: Flutter's own worker only unregisters itself and
// reloads the page, which would remove ours (sw.js, registered in
// index.html) at the same scope.
_flutter.loader.load();
