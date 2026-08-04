import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'admin_api_service.dart';
import 'app_config.dart';
import 'local_kiosk_store.dart';
import 'log_file_util.dart';

/// Tracks connectivity and flushes queued admin mutations when back online.
class OfflineSyncService {
  OfflineSyncService._();

  static final OfflineSyncService instance = OfflineSyncService._();

  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _flushing = false;

  bool get isOnline => _online;

  Future<void> start() async {
    if (kIsWeb) return;
    await refreshConnectivity();
    _sub ??= Connectivity().onConnectivityChanged.listen((_) {
      refreshConnectivity();
    });
  }

  Future<void> refreshConnectivity() async {
    if (kIsWeb) {
      _online = true;
      return;
    }
    final results = await Connectivity().checkConnectivity();
    final hadLink = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile,
    );
    if (!hadLink) {
      _online = false;
      return;
    }
    _online = await _pingCloud();
    if (_online) {
      unawaited(flushPendingMutations());
    }
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
    if (!await _pingCloud()) return 0;

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
