import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/machine_slot.dart';
import 'app_config.dart';

/// Integración con Reyeah Open API.
///
/// Documentación: OpenController Customer Integration Document (2026-04-30)
/// Base URL test: https://api-testwm.reyeah.com
///
/// Autenticación: HMAC-SHA1 + MD5 signing
///   Headers requeridos: appId, nonce, timeStamp, version (1.0.1), sign
///
/// Flujo de compra:
///   1. getProducts()   → lista de slots; cada slot tiene externalId = records[].id
///   2. createOrder()   → devuelve orderNo (params como query string, sin JSON body)
///   3. shipment()      → confirma el despacho físico (JSON body)
class ReyeahService {
  static String get _baseUrl   => AppConfig.vmBaseUrl;
  static String get _appId     => AppConfig.vmAppId;
  static String get _appSecret => AppConfig.vmAppSecret;
  static String get _machineNo => AppConfig.vmMachineNo;

  static const String _version = '1.0.1';

  // ── Firma ──────────────────────────────────────────────────────────────────

  static String _nonce() {
    final rand = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(16, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Genera la firma:
  ///   source = sort_asc(headerParams ∪ extraParams).map(k=URLencode(v)).join('&') + rawBody
  ///   sign   = MD5(HmacSHA1(source, appSecret)).toUpperCase()
  static String _buildSign({
    required Map<String, String> headerParams,
    Map<String, String> extraParams = const {},
    String rawBody = '',
  }) {
    final all = <String, String>{...headerParams, ...extraParams};

    final sorted = all.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paramStr = sorted
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final signData = paramStr + rawBody;

    // DEBUG — remove before production
    // ignore: avoid_print
    print('[ReyeahSign] source: $signData');

    final hmacBytes =
        Hmac(sha1, utf8.encode(_appSecret)).convert(utf8.encode(signData)).bytes;
    final result = md5.convert(hmacBytes).toString().toUpperCase();

    // ignore: avoid_print
    print('[ReyeahSign] sign:   $result');
    return result;
  }

  /// Devuelve los 5 headers de autenticación para un endpoint JSON-body.
  static Map<String, String> _buildJsonHeaders({
    required Map<String, dynamic> body,
    Map<String, String> queryParams = const {},
  }) {
    final nonce = _nonce();
    final ts    = DateTime.now().millisecondsSinceEpoch.toString();

    final headerParams = {
      'appId':     _appId,
      'nonce':     nonce,
      'timeStamp': ts,
      'version':   _version,
    };

    final rawBody = body.isEmpty ? '' : jsonEncode(body);
    final sign = _buildSign(
      headerParams: headerParams,
      extraParams:  queryParams,
      rawBody:      rawBody,
    );

    return {
      'appId':        _appId,
      'nonce':        nonce,
      'timeStamp':    ts,
      'version':      _version,
      'sign':         sign,
      'Content-Type': 'application/json',
      'Accept':       'application/json',
    };
  }

  /// Devuelve los 5 headers de autenticación para un endpoint query/form.
  /// Los queryParams participan en la firma pero el body string queda vacío.
  static Map<String, String> _buildQueryHeaders(Map<String, String> queryParams) {
    final nonce = _nonce();
    final ts    = DateTime.now().millisecondsSinceEpoch.toString();

    final headerParams = {
      'appId':     _appId,
      'nonce':     nonce,
      'timeStamp': ts,
      'version':   _version,
    };

    final sign = _buildSign(
      headerParams: headerParams,
      extraParams:  queryParams,
    );

    return {
      'appId':     _appId,
      'nonce':     nonce,
      'timeStamp': ts,
      'version':   _version,
      'sign':      sign,
      'Accept':    'application/json',
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static void _checkCode(Map<String, dynamic> data, String rawBody) {
    final code = data['code'];
    if (code != 0) {
      final msg = data['msg']?.toString() ?? 'Unknown error (code $code)';
      throw Exception('$msg\n\nRaw response:\n$rawBody');
    }
  }

  // ── Verificación de credenciales ───────────────────────────────────────────

  static Future<String?> testCredentials() async {
    try {
      await getProducts();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  // ── Endpoints ──────────────────────────────────────────────────────────────

  /// POST /open/getProductByPage — lista de slots de la máquina.
  static Future<MachineSlotsResponse> getProducts() async {
    final body    = <String, dynamic>{'machineNo': _machineNo, 'currentPage': 1, 'pageSize': 100};
    final headers = _buildJsonHeaders(body: body);
    final uri     = Uri.parse('$_baseUrl/open/getProductByPage');

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}\n\nRaw response:\n${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _checkCode(data, response.body);

    final inner   = data['data'] as Map<String, dynamic>? ?? {};
    final rawList = inner['records'] as List? ?? [];

    final slots = rawList.map((p) {
      final map     = p as Map<String, dynamic>;
      final stock   = (map['nowStock'] as num?)?.toInt() ?? 0;
      final isFault = map['isFault']?.toString() == '1';
      return MachineSlot(
        lineNumber:   (map['lineNum'] as num).toInt(),
        externalId:   map['id']?.toString(),           // records[].id → machineLineProductId
        productName:  map['productName'] as String? ?? 'Product',
        productImage: map['image'] as String?,
        price:        (map['retailPrice'] as num?)?.toDouble() ?? 0.0,
        currentStock: stock,
        maxStock:     (map['maxStock'] as num?)?.toInt() ?? 0,
        isAvailable:  !isFault && stock > 0,
        isFault:      isFault,
      );
    }).toList();

    return MachineSlotsResponse(
      machineNumber: _machineNo,
      machineName:   'VMFS Machine',
      slots:         slots,
    );
  }

  /// POST /open/createOrder — crea una orden. Usa query params, NO JSON body.
  static Future<String> createOrder({
    required String machineLineProductId,
  }) async {
    final queryParams = {
      'machineNo':            _machineNo,
      'machineLineProductId': machineLineProductId,
    };
    final headers = _buildQueryHeaders(queryParams);
    final uri     = Uri.parse('$_baseUrl/open/createOrder')
        .replace(queryParameters: queryParams);

    final response = await http
        .post(uri, headers: headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}\n\nRaw response:\n${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _checkCode(data, response.body);

    final orderNo = data['data']?['orderNo'] as String?;
    if (orderNo == null || orderNo.isEmpty) {
      throw Exception('Order created but no orderNo returned.\n\nRaw response:\n${response.body}');
    }
    return orderNo;
  }

  /// POST /open/shipment — confirma el despacho físico del producto.
  static Future<void> shipment(String orderNo) async {
    final body    = <String, dynamic>{'orderNo': orderNo};
    final headers = _buildJsonHeaders(body: body);
    final uri     = Uri.parse('$_baseUrl/open/shipment');

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}\n\nRaw response:\n${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _checkCode(data, response.body);
  }

  /// POST /open/getOrder — consulta el estado de una orden.
  static Future<Map<String, dynamic>> getOrder(String orderNo) async {
    final body    = <String, dynamic>{'orderNo': orderNo};
    final headers = _buildJsonHeaders(body: body);
    final uri     = Uri.parse('$_baseUrl/open/getOrder');

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}\n\nRaw response:\n${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _checkCode(data, response.body);

    return data['data'] as Map<String, dynamic>? ?? {};
  }
}
