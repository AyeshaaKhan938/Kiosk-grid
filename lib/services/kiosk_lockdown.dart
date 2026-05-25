import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the native Android side to enter/exit Lock Task Mode
/// (screen pinning). No-op on web/desktop — those platforms have no concept
/// of a vending-machine kiosk lockdown.
class KioskLockdown {
  KioskLockdown._();

  static const _channel = MethodChannel('vmfs.kiosk/lockdown');

  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Unlocks the device so an operator can install updates, reach Android
  /// Settings, etc. After this call the customer can press Home / Recents.
  /// To re-lock, simply restart the app or call [enterKioskMode].
  static Future<bool> exitKioskMode() async {
    if (!_isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('exitKioskMode');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Re-pins the screen. Used after an admin action when we want to drop
  /// straight back into customer-facing lockdown.
  static Future<bool> enterKioskMode() async {
    if (!_isSupported) return false;
    try {
      final pinned = await _channel.invokeMethod<bool>('enterKioskMode');
      return pinned ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Reports whether the activity is currently pinned. Useful for showing
  /// admins whether their last "Exit Kiosk Mode" actually succeeded.
  static Future<bool> isInKioskMode() async {
    if (!_isSupported) return false;
    try {
      final pinned = await _channel.invokeMethod<bool>('isInKioskMode');
      return pinned ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Master kiosk-mode flag on the native side. When set to false, the
  /// activity's onResume / onWindowFocusChanged stop re-pinning, the
  /// immersive system-bar hiding is disabled, and Back / Home / Recents
  /// keys pass through to Android normally.
  ///
  /// Used by the setup wizard so the admin can drop into Android
  /// Settings → Wi-Fi during initial provisioning, then come back. After
  /// the wizard saves its final step we flip this back to true and
  /// kiosk lockdown takes over for the customer-facing screens.
  static Future<bool> setKioskModeAllowed(bool allowed) async {
    if (!_isSupported) return true;
    try {
      final ok = await _channel.invokeMethod<bool>(
          'setKioskModeAllowed', {'allowed': allowed});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android's Wi-Fi settings page. Only works when kiosk mode is
  /// off (Lock Task Mode blocks intents to other packages), so the
  /// setup wizard calls [setKioskModeAllowed] false first.
  static Future<bool> openWifiSettings() async {
    if (!_isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openWifiSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android's main Settings page. Same Lock Task Mode caveat as
  /// [openWifiSettings].
  static Future<bool> openSettings() async {
    if (!_isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
