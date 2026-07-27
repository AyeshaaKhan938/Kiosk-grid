import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

/// Servicio para los endpoints admin de vmsf-cloud.
///
/// Todos los endpoints requieren el Bearer token de gestión
/// (AppConfig.managementToken) bajo /api/v1/admin/.
///
/// NOTA: managementToken es independiente del lotteryToken.
/// El lotteryToken habilita el botón de sorteo para clientes;
/// el managementToken permite gestionar la máquina desde el Admin Panel.
class AdminApiService {
  static String get _base      => AppConfig.apiBaseUrl;
  static String get _machine   => AppConfig.machineNo;
  static String get _token     => AppConfig.managementToken;

  static bool get hasToken => _token.isNotEmpty;

  static Map<String, String> get _headers {
    if (_token.isEmpty) {
      throw Exception(
        'Management token not configured.\n'
        'Go to Admin Settings → Management Token to set it up.',
      );
    }
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type':  'application/json',
      'Accept':        'application/json',
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _get(String path,
      {Map<String, String>? query}) async {
    var uri = Uri.parse('$_base/admin/$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final res = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _parse(res);
  }

  static Future<Map<String, dynamic>> _patch(
      String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/admin/$path');
    final res = await http
        .patch(uri, headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _parse(res);
  }

  static Map<String, dynamic> _parse(http.Response res) {
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw Exception(
          data['message'] ?? 'Error ${res.statusCode}\n${res.body}');
    }
    return data;
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDashboard() =>
      _get('machines/$_machine/dashboard');

  // ── Inventario ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAdminSlots() =>
      _get('machines/$_machine/slots');

  static Future<Map<String, dynamic>> updateSlot(
          int slotId, Map<String, dynamic> fields) =>
      _patch('slots/$slotId', fields);

  /// Decrement one unit of stock for the slot at [lineNumber] in vms-cloud,
  /// mirroring what a real sale does. Used by Test Dispense so that a verified
  /// vend is also reflected in inventory.
  ///
  /// Returns the slot's new stock value, or `null` if no slot matched
  /// [lineNumber]. Returns `0` (without a write) when the slot was already
  /// empty, so the caller can surface "no stock to decrement".
  static Future<int?> decrementSlotStock(int lineNumber) async {
    final data = await getAdminSlots();
    final slots = (data['slots'] as List? ?? []).cast<Map<String, dynamic>>();

    Map<String, dynamic>? slot;
    for (final s in slots) {
      if ((s['line_number'] as num?)?.toInt() == lineNumber) {
        slot = s;
        break;
      }
    }
    if (slot == null) return null;

    final id = slot['id'] as int?;
    if (id == null) return null;

    final current = (slot['current_stock'] as num?)?.toInt() ?? 0;
    if (current <= 0) return 0;

    final newStock = current - 1;
    await updateSlot(id, {'current_stock': newStock});
    return newStock;
  }

  /// Set every slot's [current_stock] to its [max_stock] in vms-cloud.
  static Future<int> restockAllSlots() async {
    final data = await getAdminSlots();
    final slots = (data['slots'] as List? ?? []).cast<Map<String, dynamic>>();
    var updated = 0;

    for (final slot in slots) {
      final id = slot['id'] as int?;
      final max = slot['max_stock'] as int? ?? 0;
      if (id == null || max <= 0) continue;

      final current = slot['current_stock'] as int? ?? 0;
      if (current >= max) continue;

      await updateSlot(id, {'current_stock': max});
      updated++;
    }

    return updated;
  }

  // ── Órdenes ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getOrders({
    int page       = 1,
    String? status,   // 'completed' | 'failed'
    String? date,     // 'YYYY-MM-DD'
    int perPage    = 20,
  }) {
    final q = <String, String>{
      'page':     '$page',
      'per_page': '$perPage',
      if (status != null) 'status': status,
      if (date   != null) 'date':   date,
    };
    return _get('machines/$_machine/orders', query: q);
  }

  // ── Productos ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getProducts({
    String? search,
    bool?   activeOnly,
    int     page    = 1,
    int     perPage = 50,
  }) {
    final q = <String, String>{
      'page':     '$page',
      'per_page': '$perPage',
      if (search != null && search.isNotEmpty) 'search': search,
      if (activeOnly != null) 'active': activeOnly ? '1' : '0',
    };
    return _get('products', query: q);
  }

  static Future<Map<String, dynamic>> createProduct(
          Map<String, dynamic> fields) =>
      _post('products', fields);

  static Future<Map<String, dynamic>> updateProduct(
          int productId, Map<String, dynamic> fields) =>
      _patch('products/$productId', fields);

  // ── HTTP helpers (private) ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/admin/$path');
    final res = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _parse(res);
  }
}
