import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'app_config.dart';

/// AFEN VMC Protocol V2.5 — motor vend only (FunCode HTTP).
///
/// Product catalog, ads, stock and prices come from vms-cloud. This service
/// only authorizes physical vends (FunCode 2000) and reports delivery (5000).
class AfenVmcService {
  static String get _vmcUrl => AppConfig.afenVmcUrl;
  static String get _machineId => AppConfig.afenMachineId;

  static final _rng = Random.secure();

  static String _tradeNo() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static String _sessionCode() {
    final n = _rng.nextInt(90000000) + 10000000;
    return '$n';
  }

  static Future<Map<String, dynamic>> _postFunCode(
    Map<String, dynamic> body,
  ) async {
    if (_vmcUrl.isEmpty) {
      throw Exception('AFEN VMC server URL is not configured.');
    }
    if (_machineId.isEmpty) {
      throw Exception('AFEN Machine ID is not configured.');
    }

    final payload = {...body, 'MachineID': _machineId};
    final uri = Uri.parse(_vmcUrl);
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('AFEN VMC HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid AFEN VMC response.');
    }
    return data;
  }

  static bool _isOk(Map<String, dynamic> data) =>
      data['Status']?.toString() == '0';

  /// FunCode 2000 — authorize pickup / vend for [slotNo].
  static Future<Map<String, dynamic>> identifyPassword({
    required int slotNo,
    required String price,
    String? tradeNo,
    String? sessionCode,
  }) async {
    final trade = tradeNo ?? _tradeNo();
    final session = sessionCode ?? _sessionCode();
    return _postFunCode({
      'FunCode': '2000',
      'TradeNo': trade,
      'SessionCode': session,
      'SlotNo': '$slotNo',
      'Price': price,
    });
  }

  /// FunCode 5000 — delivery result feedback after motor completes.
  static Future<Map<String, dynamic>> deliveryFeedback({
    required String tradeNo,
    required int slotNo,
    required bool success,
    required String amount,
    String? productId,
    String? productName,
  }) async {
    return _postFunCode({
      'FunCode': '5000',
      'TradeNo': tradeNo,
      'SlotNo': '$slotNo',
      'Status': success ? 0 : 1,
      'Time': AfenVmcService._nowString(),
      'Amount': amount,
      if (productId != null) 'ProductID': productId,
      if (productName != null) 'Name': productName,
      'PayType': 1,
    });
  }

  /// FunCode 8000 — generate payment QR (integral / cashless exchange).
  static Future<Map<String, dynamic>> integralExchange({
    required int slotNo,
    required String price,
    String? tradeNo,
    String? notifyUrl,
  }) async {
    return _postFunCode({
      'FunCode': '8000',
      'TradeNo': tradeNo ?? _tradeNo(),
      'SlotNo': '$slotNo',
      'Price': price,
      if (notifyUrl != null) 'NotifyUrl': notifyUrl,
    });
  }

  /// FunCode 9000 — poll payment result.
  static Future<Map<String, dynamic>> checkPayResult(String tradeNo) async {
    return _postFunCode({
      'FunCode': '9000',
      'TradeNo': tradeNo,
    });
  }

  /// Full vend: authorize (2000) → optional physical motor elsewhere → feedback (5000).
  static Future<bool> authorizeAndReportVend({
    required int slotNo,
    required double price,
    required bool physicalSuccess,
    String? productId,
    String? productName,
  }) async {
    final tradeNo = _tradeNo();
    final priceStr = price.toStringAsFixed(2);

    final auth = await identifyPassword(
      slotNo: slotNo,
      price: priceStr,
      tradeNo: tradeNo,
    );
    if (!_isOk(auth)) return false;

    final feedback = await deliveryFeedback(
      tradeNo: tradeNo,
      slotNo: slotNo,
      success: physicalSuccess,
      amount: priceStr,
      productId: productId,
      productName: productName,
    );
    return _isOk(feedback);
  }

  /// Returns null when the VMC endpoint is reachable and returns JSON.
  static Future<String?> testVmcEndpoint() async {
    if (_vmcUrl.isEmpty) {
      return 'VMC Server URL is required.';
    }
    if (_machineId.isEmpty) {
      return 'Machine ID is required.';
    }
    try {
      final data = await _postFunCode({
        'FunCode': '9000',
        'TradeNo': 'connectivity-test',
      });
      return data.containsKey('Status') ? null : 'Unexpected VMC response.';
    } catch (e) {
      return e.toString();
    }
  }

  static String _nowString() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}${two(n.hour)}'
        '${two(n.minute)}${two(n.second)}';
  }
}
