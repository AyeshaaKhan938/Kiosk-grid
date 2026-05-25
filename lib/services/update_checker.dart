import 'package:flutter/foundation.dart';

import 'app_config.dart';
import 'log_file_util.dart';
import 'update_service.dart';
import 'vending_machine_service.dart';

/// App-wide, lazy singleton that holds the most recent update-check result.
///
/// Other widgets can subscribe via [notifier] to react when a new APK
/// becomes available (e.g. the idle screen shows a discreet "Update
/// available" badge).
///
/// We auto-check on every app launch and then once an hour while the
/// kiosk runs. When [AppConfig.autoUpdate] is enabled (default) and a
/// newer release is found, the checker also auto-downloads and silently
/// reinstalls via `su pm install -r` — same OTA flow factory.apk uses.
/// The admin "Auto-update" tile turns this off if a bad release ever
/// needs to be quarantined.
class UpdateChecker {
  UpdateChecker._();
  static final UpdateChecker instance = UpdateChecker._();

  final ValueNotifier<UpdateInfo?> notifier = ValueNotifier<UpdateInfo?>(null);
  bool _started = false;
  bool _installing = false;

  /// Versions we already tried to install this session that failed. Stops
  /// us re-downloading the same broken APK every hour and burning the
  /// customer's mobile data on it.
  final Set<int> _failedVersionCodes = <int>{};

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
    UpdateInfo info;
    try {
      info = await UpdateService.check();
      notifier.value = info.available ? info : null;
    } catch (_) {
      // Network errors are expected when offline — don't clobber a
      // previously discovered update if this single attempt failed.
      return;
    }

    if (!info.available) return;
    if (!AppConfig.autoUpdate) return;
    if (_installing) return;
    if (_failedVersionCodes.contains(info.versionCode)) return;

    // Fire-and-forget — _autoInstall internally waits for an idle
    // dispense window before pulling the trigger.
    _autoInstall(info);
  }

  Future<void> _autoInstall(UpdateInfo info) async {
    _installing = true;
    try {
      LogFileUtil.i('update.auto.start', {
        'version': info.versionName,
        'code': info.versionCode.toString(),
        'mandatory': info.mandatory.toString(),
      });

      // Don't yank the APK while a motor is turning. Wait up to 5 min
      // for any in-flight dispense (customer / admin / heartbeat) to
      // finish; bail and retry next hour if it never quiets down.
      final waitStarted = DateTime.now();
      while (VendingMachineService.isBusy) {
        if (DateTime.now().difference(waitStarted) >
            const Duration(minutes: 5)) {
          LogFileUtil.w('update.auto.skipped_busy', {
            'version': info.versionName,
          });
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 10));
      }

      final String path;
      try {
        path = await UpdateService.download(info);
      } catch (e, st) {
        _failedVersionCodes.add(info.versionCode);
        LogFileUtil.e('update.auto.download_failed', error: e, stack: st);
        return;
      }

      LogFileUtil.i('update.auto.downloaded', {'path': path});

      final ok = await UpdateService.installApkSilent(path);
      if (ok) {
        // pm install -r will kill us in a moment. Last log line we'll
        // write in this process — the new APK reads back the log file
        // on next boot for trace continuity.
        LogFileUtil.i('update.auto.installed_silently', {
          'version': info.versionName,
        });
        return;
      }

      // su / pm install path failed — likely no root grant for our
      // package. Don't retry the silent path on the same version this
      // session, and don't fall back to the dialog flow either
      // (defeats the "no admin interaction" requirement). The admin
      // "Check for Updates" tile is still there as a manual escape
      // hatch if the operator wants to install via the system dialog.
      _failedVersionCodes.add(info.versionCode);
      LogFileUtil.w('update.auto.silent_install_failed', {
        'version': info.versionName,
        'note': 'su/pm install -r returned non-zero — package likely '
            'lacks Magisk root grant. Toggle off Auto-update or grant '
            'su via Magisk to recover.',
      });
    } finally {
      _installing = false;
    }
  }
}
