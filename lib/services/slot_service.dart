import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/machine_slot.dart';
import 'app_config.dart';
import 'reyeah_service.dart';
import 'afen_open_platform_service.dart';

/// Obtiene el inventario de slots de la máquina.
///
/// Selecciona automáticamente el backend según [AppConfig.backendMode]:
///   'vmscloud' → GET /api/v1/machines/{machineNo}/slots  (backend Laravel)
///   'reyeah'   → POST /open/getProductByPage             (Reyeah Cloud)
///   'afen'     → POST /api/deviceSlot/getDeviceSlotList  (AFEN Open Platform)
///   'tcn'      → GET /api/v1/machines/{machineNo}/slots  (vms-cloud catalog)
class SlotService {
  static String get _baseUrl   => AppConfig.apiBaseUrl;
  static String get _machineNo => AppConfig.machineNo;

  /// Devuelve la lista de slots con productos disponibles.
  /// Lanza excepción si la máquina no existe o hay error de red.
  static Future<MachineSlotsResponse> fetchSlots([String? machineNo]) async {
    switch (AppConfig.backendMode) {
      case 'reyeah':
        return ReyeahService.getProducts();
      case 'afen':
        return AfenOpenPlatformService.fetchSlots();
      case 'tcn':
      case 'vmscloud':
      default:
        return _fetchFromVmsCloud(machineNo);
    }
  }

  // ── vms-cloud (Laravel) ────────────────────────────────────────────────────

  static Future<MachineSlotsResponse> _fetchFromVmsCloud([String? machineNo]) async {
    final no  = machineNo ?? _machineNo;
    final url = Uri.parse('$_baseUrl/machines/$no/slots');

    final response = await http
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return MachineSlotsResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } else if (response.statusCode == 404) {
      throw Exception('machine_not_found');
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }
}
