import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wrapper around the native PARTIAL_WAKE_LOCK channel.
///
/// Use around any operation that must not be CPU-suspended mid-flight:
/// dispense, OTA download/install, board-status query, etc.
///
///   await DispenseWakeLock.acquire('dispense', timeout: Duration(seconds: 30));
///   try {
///     // ... do the work ...
///   } finally {
///     await DispenseWakeLock.release('dispense');
///   }
///
/// Tags scope the locks so different operations can hold them
/// independently — releasing 'dispense' won't drop a lock held under
/// 'update_install'.
class DispenseWakeLock {
  DispenseWakeLock._();

  static const _channel = MethodChannel('vmfs.kiosk/wake_lock');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Acquire a wake lock under [tag]. The OS automatically releases it
  /// after [timeout] as a safety net in case the calling code fails to
  /// `release()` (e.g. the activity is killed mid-dispense).
  static Future<bool> acquire(
    String tag, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('acquire', {
        'tag': tag,
        'timeoutMs': timeout.inMilliseconds,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Release the wake lock previously acquired under [tag]. Safe to
  /// call even if nothing was ever acquired (returns true).
  static Future<bool> release(String tag) async {
    if (!_isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('release', {'tag': tag});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Convenience: run [body] with a wake lock held under [tag],
  /// guaranteeing release no matter how [body] exits.
  static Future<T> guard<T>(
    String tag,
    Future<T> Function() body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await acquire(tag, timeout: timeout);
    try {
      return await body();
    } finally {
      await release(tag);
    }
  }
}
