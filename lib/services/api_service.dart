import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

/// Resultado de validar un código de lotería.
class LotteryCodeResult {
  final String code;
  final String productName;
  final String prizeName;      // tier name, e.g. "Gold", "Silver"
  final String prizeAmount;    // e.g. "4.99"
  final int?   lineNumber;     // slot físico — null si el prize no tiene slot
  final String machineNo;
  final bool   alreadyRedeemed;

  const LotteryCodeResult({
    required this.code,
    required this.productName,
    required this.prizeName,
    required this.prizeAmount,
    this.lineNumber,
    this.machineNo = '',
    this.alreadyRedeemed = false,
  });
}

class ApiService {
  static String get _baseUrl      => AppConfig.apiBaseUrl;
  static String get _lotteryToken => AppConfig.lotteryToken;

  // ── Draw (flujo original: token configurado en la app) ─────────────────────

  /// POST /api/v1/product-lottery-draw/{token}
  ///
  /// La app usa el token guardado en su configuración para obtener el
  /// siguiente código disponible de esa lotería.
  static Future<Map<String, String>> claimPrice() async {
    final url = Uri.parse('$_baseUrl/product-lottery-draw/$_lotteryToken');

    final response = await http
        .post(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'price':       data['price']?.toString()       ?? '0.00',
        'message':     data['message']?.toString()     ?? 'Congratulations!',
        'lineNumber':  data['lineNumber']?.toString()  ?? '',
        'machineNo':   data['machineNo']?.toString()   ?? '',
        'lotteryCode': data['code']?.toString()        ?? '',
      };
    } else if (response.statusCode == 404) {
      throw Exception('unavailable');
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // ── Lookup (flujo nuevo: usuario ingresa su código de cupón) ───────────────

  /// POST /api/v1/lottery-codes/lookup
  ///
  /// Valida un código de lotería físico (cupón impreso).
  /// Devuelve la info del premio y el slot de despacho.
  ///
  /// Lanza [LotteryCodeException] con mensaje descriptivo si el código
  /// es inválido, ya fue canjeado, o la lotería está expirada.
  static Future<LotteryCodeResult> lookupCode(String code) async {
    final url = Uri.parse('$_baseUrl/lottery-codes/lookup');

    final response = await http
        .post(
          url,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'code': code.trim().toUpperCase()}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body)['data'] ?? jsonDecode(response.body);

      final alreadyRedeemed = data['redeemed'] as bool? ?? false;
      final prize = data['prize'] as Map<String, dynamic>?  // respuesta actualizada
          ?? {'tier_code': data['price_tier'], 'name': data['price_tier_name'],
              'prize_amount': data['prize_amount'], 'line_number': data['line_number']};

      return LotteryCodeResult(
        code:            data['code'] as String? ?? code,
        productName:     (data['product'] as Map?)?['name'] as String? ?? '',
        prizeName:       prize['name'] as String?
                         ?? prize['tier_code'] as String? ?? '',
        prizeAmount:     prize['prize_amount']?.toString() ?? '0.00',
        lineNumber:      prize['line_number'] as int?,
        machineNo:       data['machine_no'] as String? ?? AppConfig.machineNo,
        alreadyRedeemed: alreadyRedeemed,
      );
    } else if (response.statusCode == 404) {
      throw LotteryCodeException('Code not found. Check the code and try again.');
    } else if (response.statusCode == 422) {
      final body = _tryDecode(response.body);
      final msg = body?['message'] as String? ?? 'This code cannot be used right now.';
      throw LotteryCodeException(msg);
    } else {
      throw LotteryCodeException('Server error (${response.statusCode}). Try again.');
    }
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return null; }
  }
}

/// Error descriptivo al validar un código de lotería.
class LotteryCodeException implements Exception {
  final String message;
  const LotteryCodeException(this.message);
  @override
  String toString() => message;
}
