import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kiosk touch feedback — audible click + haptic on supported hardware.
abstract final class TapFeedback {
  static final AudioPlayer _tapPlayer = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);
  static final AudioPlayer _primaryPlayer = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);

  static Future<void> play({bool sound = true, bool haptic = true}) async {
    if (haptic && !kIsWeb) {
      unawaited(HapticFeedback.mediumImpact());
    }
    if (sound) {
      unawaited(_playAsset(_tapPlayer, 'sounds/tap_click.wav'));
    }
  }

  static Future<void> playPrimary() async {
    if (!kIsWeb) {
      unawaited(HapticFeedback.heavyImpact());
    }
    unawaited(_playAsset(_primaryPlayer, 'sounds/tap_primary.wav'));
  }

  static Future<void> _playAsset(AudioPlayer player, String asset) async {
    try {
      await player.stop();
      await player.play(AssetSource(asset), volume: 0.9);
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}
