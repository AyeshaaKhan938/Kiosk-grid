import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

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

  /// Uploads a log file to vms-cloud via multipart POST.
  ///
  /// Endpoint contract (backend implementation in vms-cloud Laravel):
  ///   POST  $apiBaseUrl/machines/{machine_no}/logs
  ///   Headers:
  ///     Authorization: Bearer {MANAGEMENT_TOKEN}
  ///     Accept: application/json
  ///   Body (multipart/form-data):
  ///     log    (the .log file)
  ///   Response (200 OK):
  ///     {"ok": true, "saved_path": "...", "id": 123}
  ///
  /// Returns an [UploadResult] indicating outcome — never throws.
  /// Caller (admin UI) shows a snackbar based on the result.
  static Future<UploadResult> uploadFile(String path) async {
    if (!_isAndroid) {
      return const UploadResult.error('Uploads only supported on Android.');
    }
    final file = File(path);
    if (!await file.exists()) {
      return UploadResult.error('Log file not found at $path');
    }

    final machineNo = AppConfig.machineNo;
    if (machineNo.isEmpty) {
      return const UploadResult.error(
          'Machine number not configured — set it in Edit Configuration.');
    }
    final token = AppConfig.managementToken;
    if (token.isEmpty) {
      return const UploadResult.error(
          'Management token not configured — set it in admin.');
    }

    final url = Uri.parse('${AppConfig.apiBaseUrl}/machines/$machineNo/logs');
    final filename = path.split(RegExp(r'[/\\]')).last;
    final sizeBytes = await file.length();

    try {
      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..files.add(await http.MultipartFile.fromPath(
          'log',
          path,
          filename: filename,
        ));

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        return UploadResult.success(
          filename: filename,
          bytes: sizeBytes,
          serverBody: body,
        );
      }
      return UploadResult.error(
          'Server returned HTTP ${streamed.statusCode}: '
          '${body.length > 200 ? "${body.substring(0, 200)}…" : body}');
    } catch (e) {
      return UploadResult.error('Upload failed: $e');
    }
  }
}

/// Result of [LogFileUtil.uploadFile]. Pattern-match on [success] in
/// the admin UI to decide success vs error UX.
class UploadResult {
  final bool success;
  final String message;
  final String? filename;
  final int? bytes;

  const UploadResult.success({
    required this.filename,
    required this.bytes,
    String? serverBody,
  })  : success = true,
        message = 'Uploaded successfully.';

  const UploadResult.error(this.message)
      : success = false,
        filename = null,
        bytes = null;
}
