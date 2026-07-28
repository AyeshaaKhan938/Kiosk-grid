import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of an AI cooler shopping session (SMG-S400 / BKX16).
class BketShoppingSessionResult {
  final bool success;
  final String sessionId;
  final String? hostVideoPath;
  final String? subVideoPath;
  final String? errorMessage;

  const BketShoppingSessionResult({
    required this.success,
    required this.sessionId,
    this.hostVideoPath,
    this.subVideoPath,
    this.errorMessage,
  });

  factory BketShoppingSessionResult.fromMap(Map<dynamic, dynamic> map) {
    return BketShoppingSessionResult(
      success: map['success'] == true,
      sessionId: map['sessionId']?.toString() ?? '',
      hostVideoPath: map['hostVideoPath']?.toString(),
      subVideoPath: map['subVideoPath']?.toString(),
    );
  }
}

/// Status snapshot from the BKX lock + camera controller.
class BketCoolerStatus {
  final bool initialized;
  final bool doorOpen;
  final bool lockOpen;
  final bool hostCameraOnline;
  final bool subCameraOnline;
  final bool hostRecording;
  final bool subRecording;
  final String? cameraSdkVersion;

  const BketCoolerStatus({
    required this.initialized,
    required this.doorOpen,
    required this.lockOpen,
    required this.hostCameraOnline,
    required this.subCameraOnline,
    required this.hostRecording,
    required this.subRecording,
    this.cameraSdkVersion,
  });

  factory BketCoolerStatus.fromMap(Map<dynamic, dynamic> map) {
    return BketCoolerStatus(
      initialized: map['initialized'] == true,
      doorOpen: map['doorOpen'] == true,
      lockOpen: map['lockOpen'] == true,
      hostCameraOnline: map['hostCameraOnline'] == true,
      subCameraOnline: map['subCameraOnline'] == true,
      hostRecording: map['hostRecording'] == true,
      subRecording: map['subRecording'] == true,
      cameraSdkVersion: map['cameraSdkVersion']?.toString(),
    );
  }
}

/// Native bridge to BketLock + BketCamera SDKs on the SMG-S400 tablet.
class BketCoolerService {
  static const _channel = MethodChannel('vmfs.kiosk/bket_cooler');

  static Future<BketCoolerStatus> initialize() async {
    if (kIsWeb) {
      return const BketCoolerStatus(
        initialized: false,
        doorOpen: false,
        lockOpen: false,
        hostCameraOnline: false,
        subCameraOnline: false,
        hostRecording: false,
        subRecording: false,
      );
    }
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>('initialize');
    return BketCoolerStatus.fromMap(map ?? {});
  }

  static Future<BketCoolerStatus> getStatus() async {
    if (kIsWeb) {
      return const BketCoolerStatus(
        initialized: false,
        doorOpen: false,
        lockOpen: false,
        hostCameraOnline: false,
        subCameraOnline: false,
        hostRecording: false,
        subRecording: false,
      );
    }
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
    return BketCoolerStatus.fromMap(map ?? {});
  }

  /// After payment is verified: start recording, unlock door, wait for close.
  static Future<BketShoppingSessionResult> startShoppingSession({
    required String sessionId,
    int timeoutSec = 300,
  }) async {
    if (kIsWeb) {
      return BketShoppingSessionResult(
        success: false,
        sessionId: sessionId,
        errorMessage: 'AI cooler hardware only works on the Android tablet.',
      );
    }
    try {
      final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startShoppingSession',
        {'sessionId': sessionId, 'timeoutSec': timeoutSec},
      );
      return BketShoppingSessionResult.fromMap(map ?? {});
    } on PlatformException catch (e) {
      return BketShoppingSessionResult(
        success: false,
        sessionId: sessionId,
        errorMessage: e.message ?? e.toString(),
      );
    }
  }

  static Future<bool> testUnlock() async {
    if (kIsWeb) return false;
    try {
      final map =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('testUnlock');
      return map?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> release() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}
