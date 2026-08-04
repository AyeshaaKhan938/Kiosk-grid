import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'local_kiosk_store.dart';
import 'offline_sync_service.dart';

/// Servicio para los endpoints admin de vmsf-cloud.
///
/// When offline (or cloud unreachable), reads/writes [LocalKioskStore] and
/// queues mutations for later sync.
class AdminApiService {
  static String get _base      => AppConfig.apiBaseUrl;
  static String get _machine   => AppConfig.machineNo;
  static String get _token     => AppConfig.managementToken;

  static bool get hasToken => _token.isNotEmpty;

  static bool get canUseLocalAdmin =>
      LocalKioskStore.instance.hasSnapshot || hasToken;

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

  static Future<bool> _cloudReachable() async {
    if (!hasToken) return false;
    await OfflineSyncService.instance.refreshConnectivity();
    return OfflineSyncService.instance.isOnline;
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

  static Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/admin/$path');
    final res = await http
        .post(uri, headers: _headers, body: jsonEncode(body))
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

  /// Pull fresh admin + catalog snapshots from cloud after sync.
  static Future<void> refreshCloudSnapshots() async {
    if (!await _cloudReachable()) return;
    try {
      final slots = await _get('machines/$_machine/slots');
      await LocalKioskStore.instance.saveAdminSlots(slots);
    } catch (_) {}
    try {
      final products = await getProducts();
      await LocalKioskStore.instance.saveProductsPage(products);
    } catch (_) {}
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getDashboard() async {
    if (await _cloudReachable()) {
      try {
        return await _get('machines/$_machine/dashboard');
      } catch (_) {}
    }
    return {
      'offline': true,
      'message': 'Dashboard requires cloud connection.',
      'pending_sync': LocalKioskStore.instance.pendingMutationCount,
    };
  }

  // ── Inventario ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAdminSlots() async {
    if (await _cloudReachable()) {
      try {
        final data = await _get('machines/$_machine/slots');
        await LocalKioskStore.instance.saveAdminSlots(data);
        return data;
      } catch (_) {}
    }
    if (LocalKioskStore.instance.hasSnapshot) {
      return LocalKioskStore.instance.loadAdminSlots()
        ..['offline'] = true;
    }
    await LocalKioskStore.instance.seedEmptyIfNeeded();
    return LocalKioskStore.instance.loadAdminSlots()..['offline'] = true;
  }

  static Future<Map<String, dynamic>> updateSlot(
          int slotId, Map<String, dynamic> fields) async {
    await LocalKioskStore.instance.applySlotPatch(slotId, fields);

    if (await _cloudReachable()) {
      try {
        final data = await syncPatchSlot(slotId, fields);
        await LocalKioskStore.instance.saveAdminSlots(
          await _get('machines/$_machine/slots'),
        );
        return data;
      } catch (_) {}
    }

    await LocalKioskStore.instance.enqueueMutation({
      'type': 'patch_slot',
      'slot_id': slotId,
      'body': fields,
    });
    return {'offline': true, 'slot_id': slotId, ...fields};
  }

  static Future<Map<String, dynamic>> syncPatchSlot(
    int slotId,
    Map<String, dynamic> fields,
  ) =>
      _patch('slots/$slotId', fields);

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
    String? status,
    String? date,
    int perPage    = 20,
  }) async {
    if (!await _cloudReachable()) {
      return {
        'offline': true,
        'data': <Map<String, dynamic>>[],
        'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
        'message': 'Order history requires cloud connection.',
      };
    }
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
  }) async {
    if (await _cloudReachable()) {
      try {
        final q = <String, String>{
          'page':     '$page',
          'per_page': '$perPage',
          if (search != null && search.isNotEmpty) 'search': search,
          if (activeOnly != null) 'active': activeOnly ? '1' : '0',
        };
        final data = await _get('products', query: q);
        await LocalKioskStore.instance.saveProductsPage(data);
        return data;
      } catch (_) {}
    }
    if (LocalKioskStore.instance.hasSnapshot) {
      return LocalKioskStore.instance.loadProductsPage()..['offline'] = true;
    }
    await LocalKioskStore.instance.seedEmptyIfNeeded();
    return LocalKioskStore.instance.loadProductsPage()..['offline'] = true;
  }

  static Future<Map<String, dynamic>> createProduct(
          Map<String, dynamic> fields) async {
    if (await _cloudReachable()) {
      try {
        final data = await syncCreateProduct(fields);
        await getProducts();
        return data;
      } catch (_) {}
    }

    await LocalKioskStore.instance.applyProductCreate(fields);
    await LocalKioskStore.instance.enqueueMutation({
      'type': 'create_product',
      'body': fields,
    });
    return {'offline': true, ...fields};
  }

  static Future<Map<String, dynamic>> syncCreateProduct(
          Map<String, dynamic> fields) =>
      _post('products', fields);

  static Future<Map<String, dynamic>> updateProduct(
          int productId, Map<String, dynamic> fields) async {
    if (await _cloudReachable()) {
      try {
        final data = await syncUpdateProduct(productId, fields);
        await getProducts();
        return data;
      } catch (_) {}
    }

    await LocalKioskStore.instance.applyProductUpdate(productId, fields);
    await LocalKioskStore.instance.enqueueMutation({
      'type': 'update_product',
      'product_id': productId,
      'body': fields,
    });
    return {'offline': true, 'id': productId, ...fields};
  }

  static Future<Map<String, dynamic>> syncUpdateProduct(
          int productId, Map<String, dynamic> fields) =>
      _patch('products/$productId', fields);
}
