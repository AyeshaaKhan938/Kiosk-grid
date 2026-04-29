import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/machine_slot.dart';
import 'app_config.dart';
import 'reyeah_service.dart';

/// Obtiene el inventario de slots de la máquina.
///
/// Selecciona automáticamente el backend según [AppConfig.backendMode]:
///   'vmscloud' → GET /api/v1/machines/{machineNo}/slots  (backend Laravel)
///   'reyeah'   → POST /open/getProduct                  (Reyeah Cloud)
class SlotService {
  static String get _baseUrl   => AppConfig.apiBaseUrl;
  static String get _machineNo => AppConfig.machineNo;

  /// Devuelve la lista de slots con productos disponibles.
  /// Lanza excepción si la máquina no existe o hay error de red.
  static Future<MachineSlotsResponse> fetchSlots([String? machineNo]) async {
    if (AppConfig.backendMode == 'reyeah') {
      return ReyeahService.getProducts();
    }
    return _fetchFromVmsCloud(machineNo);
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
