import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native /dev/ttyS* serial port.
///
/// Confirmed via the factory APK that the Reyeah Control Board on this
/// hardware is wired to the tablet's UART pins (not through a USB-to-serial
/// chip). The native side uses android-serialport-api to open the device.
///
/// All methods are no-ops on non-Android (web, desktop, iOS) and return
/// safe defaults so the UI doesn't crash when previewed in Chrome.
class TtySerial {
  TtySerial._();

  static const _channel = MethodChannel('vmfs.kiosk/tty_serial');

  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Returns all `/dev/ttyS*` and `/dev/ttyUSB*` paths the OS exposes.
  static Future<List<String>> listDevices() async {
    if (!_isSupported) return const [];
    try {
      final r = await _channel.invokeMethod<List<dynamic>>('listDevices');
      return r?.map((e) => e.toString()).toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Opens [path] at [baud]/8N1. Returns true on success.
  /// Throws [TtySerialException] with the platform's error message on failure.
  static Future<bool> open(String path, {int baud = 9600}) async {
    if (!_isSupported) {
      throw const TtySerialException(
        'TTY serial is only available on Android. Test on the physical tablet.',
      );
    }
    try {
      final r = await _channel
          .invokeMethod<bool>('open', {'path': path, 'baud': baud});
      return r ?? false;
    } on PlatformException catch (e) {
      throw TtySerialException(e.message ?? e.code);
    }
  }

  /// Writes [data] to the open port.
  static Future<bool> write(Uint8List data) async {
    if (!_isSupported) return false;
    try {
      final r = await _channel.invokeMethod<bool>('write', {'data': data});
      return r ?? false;
    } on PlatformException catch (e) {
      throw TtySerialException(e.message ?? e.code);
    }
  }

  /// Reads up to ~1024 bytes within [timeout]. Returns empty if nothing arrived.
  static Future<Uint8List> read({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (!_isSupported) return Uint8List(0);
    try {
      final r = await _channel.invokeMethod<Uint8List>(
        'read',
        {'timeoutMs': timeout.inMilliseconds},
      );
      return r ?? Uint8List(0);
    } on PlatformException catch (e) {
      throw TtySerialException(e.message ?? e.code);
    }
  }

  /// Closes the port. Safe to call multiple times.
  static Future<bool> close() async {
    if (!_isSupported) return true;
    try {
      final r = await _channel.invokeMethod<bool>('close');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether the native side currently holds an open port.
  static Future<bool> isOpen() async {
    if (!_isSupported) return false;
    try {
      final r = await _channel.invokeMethod<bool>('isOpen');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }
}

class TtySerialException implements Exception {
  final String message;
  const TtySerialException(this.message);
  @override
  String toString() => message;
}
