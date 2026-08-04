import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kiosk touch feedback — audible click + haptic on supported hardware.
abstract final class TapFeedback {
  static Future<void> play({bool sound = true, bool haptic = true}) async {
    if (haptic && !kIsWeb) {
      await HapticFeedback.mediumImpact();
    }
    if (sound) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> playPrimary() async {
    if (!kIsWeb) {
      await HapticFeedback.heavyImpact();
    }
    await SystemSound.play(SystemSoundType.click);
  }
}
