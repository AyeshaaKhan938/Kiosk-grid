import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/advertisement.dart';
import 'app_config.dart';
import 'local_kiosk_store.dart';
import 'offline_sync_service.dart';

/// Obtiene los anuncios de la máquina desde el backend vms-cloud.
///
/// Endpoint: GET /api/v1/machines/{machineNo}/advertisements
/// Respuesta: { group_id, group_name, slots: { screensaver, top, external_screen } }
///
/// Falls back to [LocalKioskStore] when cloud is unreachable.
class AdvertisementService {
  static String get _baseUrl   => AppConfig.apiBaseUrl;
  static String get _machineNo => AppConfig.machineNo;

  /// Duración por defecto de cada slide en el screensaver (si el backend no
  /// devuelve duración propia).
  static const Duration defaultSlideDuration = Duration(seconds: 8);

  /// Tiempo de inactividad (sin toques) antes de arrancar el screensaver.
  static const Duration idleTimeout = Duration(seconds: 60);

  // ── Cache en memoria ──────────────────────────────────────────────────────

  static AdvertisementsResponse? _cache;
  static DateTime? _cacheTime;
  static const Duration _cacheTtl = Duration(minutes: 10);

  /// Devuelve los anuncios de la máquina.
  ///
  /// - Usa caché durante [_cacheTtl] para no golpear la API en cada arranque.
  /// - Devuelve datos locales si no hay conexión.
  ///
  /// Pass [forceRefresh] = true to bypass the in-memory cache. The idle
  /// screen's periodic re-poll uses this so an ad updated in vms-cloud
  /// admin shows up on the kiosk within ~2 minutes — without having to
  /// wait the full [_cacheTtl] window or reboot the tablet.
  static Future<AdvertisementsResponse> fetchAds(
      [String? machineNo, bool forceRefresh = false]) async {
    if (!forceRefresh &&
        _cache != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      debugPrint('[ads] returning cached response '
          '(${_cache!.screensaver.length} screensaver + '
          '${_cache!.top.length} top)');
      return _cache!;
    }
    if (forceRefresh) debugPrint('[ads] forceRefresh=true, bypassing cache');

    final no  = machineNo ?? _machineNo;
    final url = Uri.parse('$_baseUrl/machines/$no/advertisements');
    debugPrint('[ads] GET $url');

    try {
      await OfflineSyncService.instance.refreshConnectivity();
      if (!OfflineSyncService.instance.isOnline) {
        return _localOrCache();
      }

      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      debugPrint('[ads] HTTP ${response.statusCode}, '
          'body length ${response.body.length}');

      if (response.statusCode == 200) {
        final data = AdvertisementsResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        debugPrint('[ads] parsed: group="${data.groupName}" '
            'screensaver=${data.screensaver.length} '
            'top=${data.top.length} '
            'externalScreen=${data.externalScreen.length}');
        await LocalKioskStore.instance.saveAdvertisementsResponse(data);
        _cache     = data;
        _cacheTime = DateTime.now();
        return data;
      }

      final snippet = response.body.length > 200
          ? '${response.body.substring(0, 200)}…'
          : response.body;
      debugPrint('[ads] non-200 response: $snippet');
      return _localOrCache();
    } catch (e, stack) {
      debugPrint('[ads] fetch failed: $e\n$stack');
      return _localOrCache();
    }
  }

  static AdvertisementsResponse _localOrCache() {
    final local = LocalKioskStore.instance.loadAdvertisements();
    if (!local.isEmpty) {
      _cache = local;
      _cacheTime = DateTime.now();
      return local;
    }
    return _cache ?? AdvertisementsResponse.empty;
  }

  /// Limpia la caché (útil después de cambiar la config de la máquina).
  static void clearCache() {
    _cache     = null;
    _cacheTime = null;
  }
}
