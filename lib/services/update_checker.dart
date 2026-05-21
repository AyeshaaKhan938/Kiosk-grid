import 'package:flutter/foundation.dart';

import 'update_service.dart';

/// App-wide, lazy singleton that holds the most recent update-check result.
///
/// Other widgets can subscribe via [notifier] to react when a new APK
/// becomes available (e.g. the idle screen shows a discreet "Update
/// available" badge).
///
/// We auto-check on every app launch and then once an hour while the
/// kiosk runs — that way an admin pushing a release at 9am sees the
/// banner show up by 10am at the latest without anyone having to open
/// the admin panel.
class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  final ValueNotifier<UpdateInfo?> notifier = ValueNotifier<UpdateInfo?>(null);
  bool _started = false;

  /// Trigger one immediate check, then keep polling every [interval].
  /// Safe to call multiple times — only the first call wires up the loop.
  void startBackgroundChecks({
    Duration interval = const Duration(hours: 1),
  }) {
    if (_started) return;
    _started = true;
    // Fire a check now (after a short delay so we don't compete with
    // the app's initial network calls).
    Future<void>.delayed(const Duration(seconds: 8), _runOnce);
    // Then every [interval].
    Stream<void>.periodic(interval).listen((_) => _runOnce());
  }

  /// One-shot check — caller can `await` this and read [notifier.value].
  Future<UpdateInfo?> checkNow() async {
    await _runOnce();
    return notifier.value;
  }

  Future<void> _runOnce() async {
    try {
      final info = await UpdateService.check();
      notifier.value = info.available ? info : null;
    } catch (_) {
      // Network errors are expected when offline — don't clobber a
      // previously discovered update if this single attempt failed.
    }
  }
}
