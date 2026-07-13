import 'dart:html' as html;

/// Wipe all browser storage so SharedPreferences starts fresh.
Future<void> wipeBrowserStorage() async {
  html.window.localStorage.clear();
  html.window.sessionStorage.clear();
}

/// Remove ?reset_setup=1 from the address bar after a successful reset.
void stripSetupResetQuery() {
  final href = html.window.location.href;
  final uri = Uri.parse(href);
  if (!uri.queryParameters.containsKey('reset_setup')) return;
  final clean = uri.replace(queryParameters: {}).toString();
  html.window.history.replaceState(null, '', clean);
}
