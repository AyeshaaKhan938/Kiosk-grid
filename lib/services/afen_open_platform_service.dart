import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/machine_slot.dart';
import 'afen_sign.dart';
import 'app_config.dart';

/// AFEN Open Platform REST API — Integration #1.
///
/// Endpoints:
///   POST /api/device/getDevicePage
///   POST /api/deviceSlot/getDeviceSlotList
///   POST /api/product/getProductPage
class AfenOpenPlatformService {
  static String get _baseUrl => AppConfig.afenBaseUrl;
  static String get _appId => AppConfig.afenAppId;
  static String get _appSecret => AppConfig.afenAppSecret;
  static String get _deviceId => AppConfig.afenDeviceId;
  static String get _signMethod => AppConfig.afenSignMethod;

  // ── HTTP helper ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _post(
    String path,
    String method,
    Map<String, dynamic> body,
  ) async {
    if (_appId.isEmpty || _appSecret.isEmpty) {
      throw Exception('AFEN App ID and App Secret are required.');
    }

    final bodyJson = jsonEncode(body);
    final timestamp = AfenSign.utcTimestamp();

    final queryParams = <String, String>{
      'app_id': _appId,
      'method': method,
      'timestamp': timestamp,
      'sign_method': _signMethod,
    };
    queryParams['sign'] = AfenSign.build(
      appSecret: _appSecret,
      queryParams: queryParams,
      signMethod: _signMethod,
      bodyJson: bodyJson,
    );

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (AppConfig.afenBearerToken.isNotEmpty)
              'Authorization': 'Bearer ${AppConfig.afenBearerToken}',
          },
          body: bodyJson,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'HTTP ${response.statusCode}\n\nRaw response:\n${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['isError'] == true) {
      throw Exception(
        data['errMsg']?.toString() ?? 'AFEN API error (${data['errCode']})',
      );
    }
    return data;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  static Future<String?> testCredentials() async {
    try {
      await getDevices();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  /// POST /api/device/getDevicePage
  static Future<List<Map<String, dynamic>>> getDevices({
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _post(
      '/api/device/getDevicePage',
      'getDevicePage',
      {'Page': page, 'PageSize': pageSize},
    );
    return (data['devices'] as List? ?? [])
        .cast<Map<String, dynamic>>();
  }

  /// POST /api/product/getProductPage — product catalog for name/image lookup.
  static Future<Map<String, Map<String, dynamic>>> getProductMap({
    int pageSize = 200,
  }) async {
    final data = await _post(
      '/api/product/getProductPage',
      'getProductPage',
      {'Page': 1, 'PageSize': pageSize},
    );
    final products = (data['products'] as List? ?? []).cast<Map<String, dynamic>>();
    final map = <String, Map<String, dynamic>>{};
    for (final p in products) {
      final id = p['prId']?.toString();
      if (id != null && id.isNotEmpty) map[id] = p;
    }
    return map;
  }

  /// POST /api/deviceSlot/getDeviceSlotList — coil/slot inventory for product grid.
  static Future<MachineSlotsResponse> fetchSlots() async {
    if (_deviceId.isEmpty) {
      throw Exception('AFEN Device ID is required (Admin → AFEN credentials).');
    }

    final slotData = await _post(
      '/api/deviceSlot/getDeviceSlotList',
      'getDeviceSlotList',
      {'DeviceId': _deviceId},
    );

    Map<String, Map<String, dynamic>> productMap = {};
    try {
      productMap = await getProductMap();
    } catch (_) {
      // Product catalog optional — slots still load with prId as name.
    }

    final rawSlots =
        (slotData['deviceSlots'] as List? ?? []).cast<Map<String, dynamic>>();

    final slots = rawSlots.map((s) {
      final slotId = (s['slotId'] as num?)?.toInt() ?? 0;
      final status = (s['slotStatus'] as num?)?.toInt() ?? 0;
      final stock = (s['extantQuantity'] as num?)?.toInt() ?? 0;
      final capacity = (s['capacity'] as num?)?.toInt() ?? 0;
      final prId = s['prId']?.toString() ?? '';
      final price = (s['mPrice'] as num?)?.toDouble() ?? 0.0;

      final product = prId.isNotEmpty ? productMap[prId] : null;
      final name = product?['prName']?.toString() ??
          (prId.isNotEmpty ? 'Product $prId' : 'Slot $slotId');
      final image = product?['prImgUrl']?.toString();

      // slotStatus: 1=Normal, 2=Fault, 3=Inactive, 4=Out of stock
      final isFault = status == 2;
      final isInactive = status == 3;
      final isAvailable = !isFault && !isInactive && stock > 0;

      return MachineSlot(
        lineNumber: slotId,
        productId: int.tryParse(prId),
        externalId: prId.isNotEmpty ? prId : null,
        productName: name,
        productImage: image,
        price: price,
        currentStock: stock,
        maxStock: capacity > 0 ? capacity : 1,
        isAvailable: isAvailable,
        isFault: isFault,
      );
    }).toList()
      ..sort((a, b) => a.lineNumber.compareTo(b.lineNumber));

    String machineName = 'AFEN Machine';
    try {
      final devices = await getDevices(pageSize: 50);
      for (final d in devices) {
        if (d['mid']?.toString() == _deviceId) {
          machineName = d['deviceName']?.toString() ?? machineName;
          break;
        }
      }
    } catch (_) {}

    return MachineSlotsResponse(
      machineNumber: _deviceId,
      machineName: machineName,
      slots: slots,
    );
  }
}
