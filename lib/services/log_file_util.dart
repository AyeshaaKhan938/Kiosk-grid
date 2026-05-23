import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart wrapper around the LogFileChannel native code.
///
/// Mirrors factory.apk's `com.yy.tools.util.LogFileUtil` — writes a
/// date-rotated text file into the app's external-files dir, survives
/// crashes / restarts, and is the single source of truth when a client
/// reports an issue we can't reproduce locally.
///
/// Usage (drop in next to debugPrint at any important branch):
///   await LogFileUtil.i('dispense.start', {'slot': 5});
///   await LogFileUtil.e('dispense.failed', error: e);
///
/// Calls are fire-and-forget (Future ignored) on hot paths — never
/// block UI on disk I/O.
class LogFileUtil {
  LogFileUtil._();

  static const _channel = MethodChannel('vmfs.kiosk/log_file');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Append a structured log line. `tag` is a short event identifier
  /// (e.g. "dispense.start", "tty.open", "update.download"). `extra` is
  /// optional key=value pairs serialized inline.
  static Future<void> i(String tag, [Map<String, Object?>? extra]) =>
      _write('I', tag, extra: extra);

  static Future<void> w(String tag, [Map<String, Object?>? extra]) =>
      _write('W', tag, extra: extra);

  static Future<void> e(String tag,
          {Map<String, Object?>? extra, Object? error, StackTrace? stack}) =>
      _write('E', tag, extra: extra, error: error, stack: stack);

  static Future<void> _write(
    String level,
    String tag, {
    Map<String, Object?>? extra,
    Object? error,
    StackTrace? stack,
  }) async {
    final buf = StringBuffer('[$level] $tag');
    if (extra != null && extra.isNotEmpty) {
      buf.write('  {');
      var first = true;
      extra.forEach((k, v) {
        if (!first) buf.write(', ');
        first = false;
        buf.write('$k=$v');
      });
      buf.write('}');
    }
    if (error != null) buf.write('  error=$error');
    if (stack != null) buf.write('\n$stack');

    final line = buf.toString();

    // Always mirror to debugPrint so dev runs still see it in the
    // flutter terminal / adb logcat.
    debugPrint(line);

    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('append', {'line': line});
    } catch (_) {
      // Best-effort. Don't let logging failures break the app.
    }
  }

  /// Returns the path of the current day's log file, for admin "View Logs"
  /// or share-via-email features.
  static Future<String?> currentPath() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('path');
    } catch (_) {
      return null;
    }
  }

  /// Returns all log files in the directory, newest first.
  static Future<List<String>> listFiles() async {
    if (!_isAndroid) return const [];
    try {
      final res = await _channel.invokeListMethod<String>('listFiles');
      return res ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Reads a log file from disk and returns its contents as a single
  /// string. Capped at [maxBytes] (default 256 KB) — files larger than
  /// the cap return only their tail with a truncation marker, so the
  /// admin UI never tries to render multi-MB blobs.
  static Future<String> readFile(String path,
      {int maxBytes = 256 * 1024}) async {
    if (!_isAndroid) return '';
    try {
      final res = await _channel.invokeMethod<String>('readFile', {
        'path': path,
        'maxBytes': maxBytes,
      });
      return res ?? '';
    } catch (_) {
      return '';
    }
  }
}
