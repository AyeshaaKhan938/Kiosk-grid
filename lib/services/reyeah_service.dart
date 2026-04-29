import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/machine_slot.dart';
import 'app_config.dart';

/// Integración con Reyeah Cloud (backend alternativo).
///
/// Documentación: Reyeah Foreign Trade API
/// Base URL: https://4020y425z1.uicp.fun (configurable en AppConfig)
///
/// Autenticación: HMAC-SHA1 + MD5 signing en headers
///   Headers requeridos: app_id, nonce, time_stamp, Sign
///
/// Flujo de compra:
///   1. getProducts()   → lista de slots con machineLineProductId
///   2. createOrder()   → devuelve orderNo
///   3. shipment()      → confirma el despacho físico
class ReyeahService {
  static String get _baseUrl   => AppConfig.vmBaseUrl;
  static String get _appId     => AppConfig.vmAppId;
  static String get _appSecret => AppConfig.vmAppSecret;
  static String get _machineNo => AppConfig.vmMachineNo;

  // ── Firma ──────────────────────────────────────────────────────────────────

  /// Genera un nonce aleatorio de 16 caracteres alfanuméricos.
  static String _nonce() {
    final rand = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(16, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Construye el valor Sign para una petición:
  ///
  ///   1. Agrupa params de header (app_id, nonce, time_stamp) + params del body
  ///   2. Ordena por clave ASCII
  ///   3. Concatena como key=URLencode(value)&... + rawBodyJson
  ///   4. HMAC-SHA1 del string resultante con app_secret como clave
  ///   5. MD5 de los bytes del HMAC → uppercase hex
  static String _buildSign({
    required Map<String, String> headerParams,
    required Map<String, dynamic> body,
  }) {
    // Combinar: headers + body (todo como String)
    final all = <String, String>{...headerParams};
    body.forEach((k, v) => all[k] = v.toString());

    // Ordenar por clave ASCII y construir param string
    final sorted = all.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paramStr = sorted
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    // Concatenar con raw body JSON
    final signData = paramStr + jsonEncode(body);

    // HMAC-SHA1
    final hmacKey  = utf8.encode(_appSecret);
    final hmacData = utf8.encode(signData);
    final hmacBytes = Hmac(sha1, hmacKey).convert(hmacData).bytes;

    // MD5 de los bytes HMAC → uppercase hex
    return md5.convert(hmacBytes).toString().toUpperCase();
  }

  /// Construye los headers completos para una petición autenticada.
  static Map<String, String> _buildHeaders(Map<String, dynamic> body) {
    final nonce = _nonce();
    final ts    = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final headerParams = {
      'app_id':     _appId,
      'nonce':      nonce,
      'time_stamp': ts,
    };

    final sign = _buildSign(headerParams: headerParams, body: body);

    return {
      'app_id':       _appId,
      'nonce':        nonce,
      'time_stamp':   ts,
      'Sign':         sign,
      'Content-Type': 'application/json',
      'Accept':       'application/json',
    };
  }

  // ── Verificación de credenciales ───────────────────────────────────────────

  /// Verifica que las credenciales actualmente guardadas en AppConfig son válidas
  /// haciendo una petición a getProduct.
  ///
  /// Devuelve null si todo está bien, o un mensaje de error si falla.
  /// El llamador debe guardar las credenciales antes de llamar a este método.
  static Future<String?> testCredentials() async {
    try {
      await getProducts();
      return null; // OK
    } catch (e) {
      // Devolver el mensaje completo sin traducir para que el proveedor
      // pueda ver la respuesta original de la API.
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  /// Traduce mensajes de error del API de Reyeah (en chino) a inglés.
  static String _translateError(String raw) {
    const map = {
      'appId不存在':          'App ID not found. Check your credentials.',
      'appId 不存在':         'App ID not found. Check your credentials.',
      'sign错误':             'Invalid signature. Verify your App Secret.',
      'sign 错误':            'Invalid signature. Verify your App Secret.',
      '签名错误':              'Signature error. Verify your App Secret.',
      '时间戳过期':            'Request timestamp expired. Check device clock.',
      '机器不存在':            'Machine number not found in Reyeah system.',
      '机器离线':              'Machine is offline.',
      '无效的appId':          'Invalid App ID.',
      '无效的机器号':          'Invalid machine number.',
      '库存不足':              'Out of stock.',
      '商品不存在':            'Product not found.',
      '订单不存在':            'Order not found.',
      '请求频率过高':          'Too many requests. Please wait.',
    };
    for (final entry in map.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }
    return raw; // Devuelve original si no hay traducción
  }

  // ── Endpoints ──────────────────────────────────────────────────────────────

  /// POST /open/getProduct
  ///
  /// Devuelve la lista de slots de la máquina desde Reyeah Cloud.
  static Future<MachineSlotsResponse> getProducts() async {
    final body    = <String, dynamic>{'machineNo': _machineNo};
    final headers = _buildHeaders(body);
    final uri     = Uri.parse('$_baseUrl/open/getProduct');

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
          'HTTP ${response.statusCode}\n\nRaw response:\n${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code = data['code'];
    if (code != 200) {
      throw Exception(
          '${data['msg'] ?? 'Unknown error (code $code)'}'
          '\n\nRaw response:\n${response.body}');
    }

    final inner   = data['data'] as Map<String, dynamic>? ?? {};
    final rawList = inner['productList'] as List? ?? [];

    final slots = rawList.map((p) {
      final map    = p as Map<String, dynamic>;
      final stock  = (map['nowStock'] as num?)?.toInt() ?? 0;
      final isFault = map['isFault'] as bool? ?? false;
      return MachineSlot(
        lineNumber:   (map['lineNum'] as num).toInt(),
        externalId:   map['machineLineProductId']?.toString(),
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
      machineName:   inner['machineName'] as String? ?? 'VMFS Machine',
      slots:         slots,
    );
  }

  /// POST /open/createOrder
  ///
  /// Crea una orden de compra en Reyeah Cloud.
  /// Devuelve el [orderNo] que luego se pasa a [shipment].
  static Future<String> createOrder({
    required String machineLineProductId,
    int buyNum = 1,
  }) async {
    final body = <String, dynamic>{
      'appVersion':            '1.0.0',
      'buyNum':                buyNum,
      'machineNo':             _machineNo,
      'machineLineProductId':  machineLineProductId,
      'payType':               '4', // tipo pago externo / kiosk
    };
    final headers = _buildHeaders(body);
    final uri     = Uri.parse('$_baseUrl/open/createOrder');

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Reyeah order error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code = data['code'];
    if (code != 200) {
      throw Exception(data['msg']?.toString() ?? 'Order creation failed (code $code)');
    }

    final orderNo = data['data']?['orderNo'] as String?;
    if (orderNo == null || orderNo.isEmpty) {
      throw Exception('Order created but no orderNo returned.');
    }
    return orderNo;
  }

  /// POST /open/shipment
  ///
  /// Confirma el despacho físico del producto en Reyeah Cloud.
  static Future<void> shipment(String orderNo) async {
    final body    = <String, dynamic>{'orderNo': orderNo};
    final headers = _buildHeaders(body);
    final uri     = Uri.parse('$_baseUrl/open/shipment');

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Reyeah shipment error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code = data['code'];
    if (code != 200) {
      throw Exception(data['msg']?.toString() ?? 'Shipment failed (code $code)');
    }
  }
}
