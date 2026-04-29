import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/advertisement.dart';
import 'app_config.dart';

/// Obtiene los anuncios de la máquina desde el backend vms-cloud.
///
/// Endpoint: GET /api/v1/machines/{machineNo}/advertisements
/// Respuesta: { group_id, group_name, slots: { screensaver, top, external_screen } }
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
  /// - Devuelve [AdvertisementsResponse.empty] si no hay conexión o la máquina
  ///   no tiene grupo de anuncios asignado.
  static Future<AdvertisementsResponse> fetchAds([String? machineNo]) async {
    // Devolver caché si sigue vigente
    if (_cache != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      return _cache!;
    }

    final no  = machineNo ?? _machineNo;
    final url = Uri.parse('$_baseUrl/machines/$no/advertisements');

    try {
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = AdvertisementsResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        _cache     = data;
        _cacheTime = DateTime.now();
        return data;
      }

      // 404 = máquina sin grupo → devolver vacío silencioso
      return AdvertisementsResponse.empty;
    } catch (_) {
      // Sin conexión → devolver caché expirado si existe, si no vacío
      return _cache ?? AdvertisementsResponse.empty;
    }
  }

  /// Limpia la caché (útil después de cambiar la config de la máquina).
  static void clearCache() {
    _cache     = null;
    _cacheTime = null;
  }
}
