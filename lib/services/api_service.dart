import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'app_config.dart';

/// Resultado de validar un código de lotería.
class LotteryCodeResult {
  final String code;
  final String productName;
  final String prizeName;      // tier name, e.g. "Grand Prize"
  final String prizeAmount;    // e.g. "10.00"
  final String tier;           // "A" or "B"
  final int?   lineNumber;     // slot físico — null si el prize no tiene slot
  final String machineNo;
  final bool   alreadyRedeemed;

  const LotteryCodeResult({
    required this.code,
    required this.productName,
    required this.prizeName,
    required this.prizeAmount,
    this.tier = '',
    this.lineNumber,
    this.machineNo = '',
    this.alreadyRedeemed = false,
  });
}

class ApiService {
  static String get _baseUrl      => AppConfig.apiBaseUrl;
  static String get _lotteryToken => AppConfig.lotteryToken;
  static String get _machineNo    => AppConfig.machineNo;

  static final math.Random _rng = math.Random.secure();

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

  // ── Lookup (Ten Point Media scratch-card flow) ─────────────────────────────

  /// POST /api/v1/scratch-card/redeem
  ///
  /// Validates the scratch-card code via Ten Point Media (server-side),
  /// records the redemption to prevent reuse, and returns tier configuration.
  /// We then roll a 1:49 weighted dice locally to pick Tier A or Tier B.
  ///
  /// Throws [LotteryCodeException] with a customer-facing message if the
  /// code is invalid, already redeemed, or the validation service is down.
  static Future<LotteryCodeResult> lookupCode(String code) async {
    final url = Uri.parse('$_baseUrl/scratch-card/redeem');
    final normalized = code.trim().toUpperCase();

    final response = await http
        .post(
          url,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'code': normalized,
            'machine_no': _machineNo,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final body  = jsonDecode(response.body) as Map<String, dynamic>;
      final tiers = (body['tiers'] as Map).cast<String, dynamic>();

      // Roll the tier (weighted) — only consider tiers with at least one
      // in-stock slot. The backend already filters by stock>0 but we double-
      // check here in case both tiers are empty (the backend rejects that case
      // with a 503 NO_STOCK before locking the code, so we shouldn't see it).
      final chosen = _rollTier(tiers);
      final tierConfig = (tiers[chosen] as Map).cast<String, dynamic>();
      final slots = (tierConfig['slots'] as List).cast<Map>();

      if (slots.isEmpty) {
        throw const LotteryCodeException(
          'Sorry, this prize is currently out of stock.',
        );
      }

      // Random slot within the chosen tier (uniform).
      final pick = slots[_rng.nextInt(slots.length)].cast<String, dynamic>();

      return LotteryCodeResult(
        code:        normalized,
        productName: pick['product_name']?.toString() ?? tierConfig['name']?.toString() ?? '',
        prizeName:   tierConfig['name']?.toString() ?? '',
        prizeAmount: '0.00',
        tier:        chosen,
        lineNumber:  _parseInt(pick['line_number']),
        machineNo:   _machineNo,
      );
    }

    if (response.statusCode == 422) {
      final body = _tryDecode(response.body);
      final msg  = body?['message'] as String? ?? 'Sorry, try again next time.';
      throw LotteryCodeException(msg);
    }

    if (response.statusCode == 503) {
      throw const LotteryCodeException(
        'Validation service unavailable. Please try again later.',
      );
    }

    throw LotteryCodeException(
      'Server error (${response.statusCode}). Please try again.',
    );
  }

  /// Reports the dispense outcome back to vms-cloud so the redemption row
  /// records which tier was rolled and whether the motor confirmed delivery.
  static Future<void> confirmScratchCard({
    required String code,
    required String tier,
    required int    lineNumber,
    required double prizeAmount,
    required bool   success,
    String? error,
  }) async {
    final url = Uri.parse('$_baseUrl/scratch-card/confirm');

    try {
      await http
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'code':         code,
              'tier':         tier,
              'line_number':  lineNumber,
              'prize_amount': prizeAmount,
              'success':      success,
              if (error != null) 'error': error,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort — don't block UX if the confirm call fails. The redemption
      // is already locked server-side; missing dispense metadata is recoverable.
    }
  }

  // ── Weighted dice ──────────────────────────────────────────────────────────

  /// Picks a tier key from the config map using its `weight` field.
  /// Tiers with weight==0 or no in-stock slots are excluded — if a customer
  /// would have won Tier A but Tier A is empty, they get Tier B instead.
  static String _rollTier(Map<String, dynamic> tiers) {
    int total = 0;
    final entries = <MapEntry<String, int>>[];
    for (final e in tiers.entries) {
      final tierMap = (e.value as Map).cast<String, dynamic>();
      final w = _parseInt(tierMap['weight']) ?? 0;
      final hasSlots = (tierMap['slots'] is List) && (tierMap['slots'] as List).isNotEmpty;
      if (w > 0 && hasSlots) {
        total += w;
        entries.add(MapEntry(e.key, w));
      }
    }
    if (total == 0 || entries.isEmpty) {
      // Both tiers empty — the backend already rejected this case with 503
      // before locking the code. Fall back to the first available key just in
      // case (the caller will then fail on empty slots).
      return tiers.keys.first;
    }

    final roll = _rng.nextInt(total);
    int acc = 0;
    for (final e in entries) {
      acc += e.value;
      if (roll < acc) return e.key;
    }
    return entries.last.key;
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return null; }
  }
}

/// Customer-facing error from a scratch-card lookup.
class LotteryCodeException implements Exception {
  final String message;
  const LotteryCodeException(this.message);
  @override
  String toString() => message;
}
