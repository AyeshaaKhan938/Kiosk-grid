import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'admin_api_service.dart';
import 'app_config.dart';
import 'kiosk_cloud_service.dart';
import 'local_kiosk_store.dart';
import 'log_file_util.dart';
import 'machine_issue_service.dart';

/// Tracks connectivity and flushes queued admin mutations when back online.
class OfflineSyncService {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();

  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _connectivityDebounce;
  bool _flushing = false;

  DateTime? _lastReachabilityCheck;
  bool _lastReachability = false;
  static const Duration _reachabilityTtl = Duration(seconds: 45);

  bool get isOnline => _online;

  /// Cached cloud reachability (link + `/kiosk/version` ping). Avoids redundant
  /// pings when slots, ads, and lottery poll in the same few seconds.
  Future<bool> isCloudReachable({bool forceRefresh = false}) async {
    if (kIsWeb) {
      _online = true;
      return true;
    }

    if (!forceRefresh &&
        _lastReachabilityCheck != null &&
        DateTime.now().difference(_lastReachabilityCheck!) < _reachabilityTtl) {
      return _lastReachability;
    }

    final results = await Connectivity().checkConnectivity();
    final hadLink = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile,
    );

    if (!hadLink) {
      _recordReachability(false);
      return false;
    }

    final reachable = await _pingCloud();
    _recordReachability(reachable);

    if (reachable) {
      unawaited(flushPendingMutations());
      unawaited(MachineIssueService.instance.flushOfflineQueue());
      unawaited(KioskCloudService.instance.heartbeat());
    }

    return reachable;
  }

  void _recordReachability(bool reachable) {
    _lastReachabilityCheck = DateTime.now();
    _lastReachability = reachable;
    _online = reachable;
  }

  Future<void> start() async {
    if (kIsWeb) return;
    await isCloudReachable(forceRefresh: true);
    _sub ??= Connectivity().onConnectivityChanged.listen((_) {
      _connectivityDebounce?.cancel();
      _connectivityDebounce = Timer(const Duration(milliseconds: 400), () {
        unawaited(isCloudReachable(forceRefresh: true));
      });
    });
  }

  Future<void> refreshConnectivity() async {
    await isCloudReachable(forceRefresh: true);
  }

  Future<bool> _pingCloud() async {
    try {
      final url = Uri.parse('${AppConfig.apiBaseUrl}/kiosk/version');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<int> flushPendingMutations() async {
    if (_flushing || !AdminApiService.hasToken) return 0;
    if (!await isCloudReachable()) return 0;

    _flushing = true;
    var synced = 0;
    try {
      final pending = LocalKioskStore.instance.pendingMutations();
      for (final m in pending) {
        final id = m['id']?.toString() ?? '';
        final type = m['type']?.toString() ?? '';
        try {
          switch (type) {
            case 'patch_slot':
              await AdminApiService.syncPatchSlot(
                (m['slot_id'] as num).toInt(),
                Map<String, dynamic>.from(m['body'] as Map),
              );
              break;
            case 'create_product':
              await AdminApiService.syncCreateProduct(
                Map<String, dynamic>.from(m['body'] as Map),
              );
              break;
            case 'update_product':
              await AdminApiService.syncUpdateProduct(
                (m['product_id'] as num).toInt(),
                Map<String, dynamic>.from(m['body'] as Map),
              );
              break;
            default:
              continue;
          }
          await LocalKioskStore.instance.removeMutation(id);
          synced++;
        } catch (e) {
          LogFileUtil.w('offline.sync.failed', {'type': type, 'error': '$e'});
        }
      }
      if (synced > 0) {
        LogFileUtil.i('offline.sync.complete', {'count': synced});
        await AdminApiService.refreshCloudSnapshots();
      }
    } finally {
      _flushing = false;
    }
    return synced;
  }
}
