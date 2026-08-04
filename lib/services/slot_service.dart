import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/machine_slot.dart';
import 'app_config.dart';
import 'local_kiosk_store.dart';
import 'reyeah_service.dart';

/// Obtiene el inventario de slots de la máquina.
///
/// Product catalog source — cloud backend only (dispense protocol is separate).
///   'vmscloud' → GET /api/v1/machines/{machineNo}/slots
///   'reyeah'   → legacy Reyeah Cloud catalog
class SlotService {
  static String get _baseUrl   => AppConfig.apiBaseUrl;
  static String get _machineNo => AppConfig.machineNo;

  /// Devuelve la lista de slots con productos disponibles.
  /// Lanza excepción si la máquina no existe o hay error de red.
  static Future<MachineSlotsResponse> fetchSlots([String? machineNo]) async {
    switch (AppConfig.backendMode) {
      case 'reyeah':
        try {
          final data = await ReyeahService.getProducts();
          await _saveCatalogSnapshot(data);
          return data;
        } catch (_) {
          return _loadLocalOrRethrow();
        }
      case 'vmscloud':
      default:
        return _fetchFromVmsCloud(machineNo);
    }
  }

  static Future<void> _saveCatalogSnapshot(MachineSlotsResponse data) async {
    await LocalKioskStore.instance.saveSlotsCatalog({
      'machine_number': data.machineNumber,
      'machine_name': data.machineName,
      'slots': data.slots
          .map((s) => {
                'line_number': s.lineNumber,
                'product_id': s.productId,
                'product_name': s.productName,
                'product_image': s.productImage,
                'product_description': s.productDescription,
                'product_brand': s.productBrand,
                'product_category': s.productCategory,
                'product_sku': s.productSku,
                'product_weight': s.productWeight,
                'product_weight_unit': s.productWeightUnit,
                'product_media': s.productMedia,
                'price': s.price,
                'current_stock': s.currentStock,
                'max_stock': s.maxStock,
                'is_available': s.isAvailable,
                'is_fault': s.isFault,
              })
          .toList(),
      'categories': data.categories
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'slug': c.slug,
                'icon_url': c.iconUrl,
                'sort_order': c.sortOrder,
              })
          .toList(),
    });
  }

  static Future<MachineSlotsResponse> _loadLocalOrRethrow() async {
    final local = LocalKioskStore.instance.loadSlotsCatalog();
    if (local != null) return local;
    await LocalKioskStore.instance.seedEmptyIfNeeded();
    return LocalKioskStore.instance.loadSlotsCatalog() ??
        (throw Exception('Could not connect to server'));
  }

  // ── vms-cloud (Laravel) ────────────────────────────────────────────────────

  static Future<MachineSlotsResponse> _fetchFromVmsCloud([String? machineNo]) async {
    final no  = machineNo ?? _machineNo;
    final url = Uri.parse('$_baseUrl/machines/$no/slots');

    try {
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        await LocalKioskStore.instance.saveSlotsCatalog(json);
        return MachineSlotsResponse.fromJson(json);
      } else if (response.statusCode == 404) {
        throw Exception('machine_not_found');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (_) {
      return _loadLocalOrRethrow();
    }
  }
}
