import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'log_file_util.dart';
import 'vending_machine_service.dart';

/// Background uploader that ships kiosk log files to vms-cloud
/// automatically — no operator interaction required.
///
/// Lifecycle:
///   - [start] is called once from main.dart after AppConfig.init().
///   - 60 s after launch, a first scan runs.
///   - Every 6 hours after that, another scan runs.
///   - Each scan lists files in the log directory, skips today's
///     (still being appended to), skips files we already uploaded, and
///     pushes the rest to vms-cloud via [LogFileUtil.uploadFile]. We
///     wait for an idle dispense window (up to 1 minute) before
///     uploading so we don't fight for the kiosk's network during a
///     customer transaction.
///
/// Idempotency:
///   - The set of already-uploaded filenames is persisted in
///     SharedPreferences under [_kUploadedSetKey]. We key by the
///     *basename* of the log file (e.g. "2026-05-23.log") rather than
///     the full path so an Android-side path change can't trick us
///     into re-uploading.
///   - On the server side, [KioskLogController] prefixes uploads with
///     a timestamp anyway, so even a re-upload doesn't overwrite
///     anything — but bandwidth + Filament noise still matter.
///
/// Kill switch:
///   - [AppConfig.autoUploadLogs] (default true). The admin
///     "Auto-upload logs" tile flips this off if logs need to stop
///     flowing for any reason.
///
/// Limits per scan:
///   - At most [_kMaxUploadsPerPulse] files. Stops a kiosk that's
///     been offline for weeks from drowning vms-cloud on first
///     reconnect — the queue drains across multiple pulses instead.
class LogAutoUploader {
  LogAutoUploader._();
  static final LogAutoUploader instance = LogAutoUploader._();

  static const _kUploadedSetKey = 'log_auto_uploaded_files';
  static const _kInitialDelay = Duration(seconds: 60);
  static const _kInterval = Duration(hours: 6);
  static const _kBusyTimeout = Duration(minutes: 1);
  static const _kMaxUploadsPerPulse = 5;

  bool _started = false;
  bool _running = false;
  Timer? _timer;

  /// Wire up the timers. Safe to call multiple times — only the first
  /// call has any effect.
  void start() {
    if (_started) return;
    _started = true;

    Future<void>.delayed(_kInitialDelay, _pulse);
    _timer = Timer.periodic(_kInterval, (_) => _pulse());
    LogFileUtil.i('log.auto.scheduler_started', {
      'initial_delay_sec': _kInitialDelay.inSeconds.toString(),
      'interval_hours': _kInterval.inHours.toString(),
    });
  }

  /// Stop the scheduler. Used by future "drain and shut down" logic;
  /// not called from anywhere today.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// One scan pass — find unuploaded log files and ship as many as
  /// the per-pulse cap allows. Never throws.
  Future<void> _pulse() async {
    if (_running) return;
    if (!AppConfig.autoUploadLogs) return;
    if (AppConfig.machineNo.isEmpty) return;
    if (AppConfig.managementToken.isEmpty) return;

    _running = true;
    try {
      // Don't fight a customer transaction for the radio. If a dispense
      // is mid-flight, wait briefly; if it stays busy past the timeout,
      // bail and retry next pulse.
      final waitStart = DateTime.now();
      while (VendingMachineService.isBusy) {
        if (DateTime.now().difference(waitStart) > _kBusyTimeout) {
          LogFileUtil.w('log.auto.skipped_busy');
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      }

      final files = await LogFileUtil.listFiles();
      if (files.isEmpty) return;

      final todayPath = await LogFileUtil.currentPath();

      final prefs = await SharedPreferences.getInstance();
      final uploaded = (prefs.getStringList(_kUploadedSetKey) ?? <String>[])
          .toSet();

      // Skip today's file (still being appended to) and anything we've
      // already uploaded. Oldest first so chronological order matches
      // on the server side.
      final pending = files
          .where((p) => p != todayPath)
          .where((p) => !uploaded.contains(_basename(p)))
          .toList()
          .reversed
          .toList();

      if (pending.isEmpty) return;

      LogFileUtil.i('log.auto.scan', {
        'pending': pending.length.toString(),
        'cap': _kMaxUploadsPerPulse.toString(),
      });

      var successes = 0;
      for (final path in pending.take(_kMaxUploadsPerPulse)) {
        // Skip empty / missing files. Don't burn the "already uploaded"
        // flag on a zero-byte file that never had content.
        final file = File(path);
        if (!await file.exists()) continue;
        final size = await file.length();
        if (size == 0) {
          uploaded.add(_basename(path));
          continue;
        }

        final result = await LogFileUtil.uploadFile(path);
        if (result.success) {
          uploaded.add(_basename(path));
          successes++;
          LogFileUtil.i('log.auto.uploaded', {
            'file': _basename(path),
            'bytes': result.bytes.toString(),
          });
        } else {
          LogFileUtil.w('log.auto.upload_failed', {
            'file': _basename(path),
            'reason': result.message,
          });
          // Stop this batch — likely the network is flaky or the
          // server is down. Next pulse will retry.
          break;
        }
      }

      await prefs.setStringList(_kUploadedSetKey, uploaded.toList());
      LogFileUtil.i('log.auto.batch_done', {
        'uploaded': successes.toString(),
        'remaining': (pending.length - successes).toString(),
      });
    } catch (e, st) {
      LogFileUtil.e('log.auto.exception', error: e, stack: st);
    } finally {
      _running = false;
    }
  }

  String _basename(String path) => path.split(RegExp(r'[/\\]')).last;
}
