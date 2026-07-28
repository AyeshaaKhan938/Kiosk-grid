import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'app_config.dart';
import '../models/cooler_session.dart';

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
  /// [ageVerificationSessionId] — required when age verification is enabled;
  /// vms-cloud checks that this session was verified 18+ before redeeming.
  ///
  /// Throws [LotteryCodeException] with a customer-facing message if the
  /// code is invalid, already redeemed, or the validation service is down.
  static Future<LotteryCodeResult> lookupCode(
    String code, {
    String? ageVerificationSessionId,
  }) async {
    final url = Uri.parse('$_baseUrl/scratch-card/redeem');
    final normalized = code.trim().toUpperCase();

    final payload = <String, dynamic>{
      'code': normalized,
      'machine_no': _machineNo,
    };
    if (ageVerificationSessionId != null &&
        ageVerificationSessionId.isNotEmpty) {
      payload['age_verification_session_id'] = ageVerificationSessionId;
    }

    final response = await http
        .post(
          url,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
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

  // ── Retail purchase (vending) ─────────────────────────────────────────────

  /// POST /api/v1/orders
  ///
  /// Creates a paid order, verifies payment server-side, and returns the
  /// slot to vend. vms-cloud must confirm payment before responding 200.
  static Future<PurchaseOrderResult> createPurchaseOrder({
    required int lineNumber,
    required double amount,
    required String productName,
    String? ageVerificationSessionId,
  }) async {
    final url = Uri.parse('$_baseUrl/orders');
    final payload = <String, dynamic>{
      'machine_no':   _machineNo,
      'line_number':  lineNumber,
      'amount':       amount,
      'product_name': productName,
      'payment_method': 'card',
    };
    if (ageVerificationSessionId != null &&
        ageVerificationSessionId.isNotEmpty) {
      payload['age_verification_session_id'] = ageVerificationSessionId;
    }

    final response = await http
        .post(
          url,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PurchaseOrderResult(
        orderId: body['order_id']?.toString() ??
            body['id']?.toString() ??
            '',
        paymentVerified: body['payment_verified'] == true ||
            body['status']?.toString() == 'paid',
        lineNumber: _parseInt(body['line_number']) ?? lineNumber,
        paymentMethod: body['payment_method']?.toString(),
        message: body['message']?.toString(),
      );
    }

    final body = _tryDecode(response.body);
    final msg = body?['message']?.toString();

    if (response.statusCode == 402) {
      throw PurchaseOrderException(
        msg ?? 'Payment declined. Please try another card.',
      );
    }
    if (response.statusCode == 422) {
      throw PurchaseOrderException(msg ?? 'Could not complete purchase.');
    }

    throw PurchaseOrderException(
      msg ?? 'Server error (${response.statusCode}). Please try again.',
    );
  }

  // ── AI cooler (SMG-S400 headless flow) ────────────────────────────────────

  /// GET /api/v1/machines/{machineNo}/cooler-sessions/pending
  ///
  /// Returns a POS-paid session waiting for the kiosk to unlock the door,
  /// or null when nothing is pending (204 / empty body / 404).
  static Future<PendingCoolerSession?> fetchPendingCoolerSession() async {
    final url = Uri.parse(
      '$_baseUrl/machines/$_machineNo/cooler-sessions/pending',
    );

    final response = await http
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 204 || response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 200) {
      final body = response.body.trim();
      if (body.isEmpty) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final session = PendingCoolerSession.fromJson(json);
      if (session.orderId.isEmpty || session.sessionId.isEmpty) {
        return null;
      }
      return session;
    }

    throw Exception('Pending session error: ${response.statusCode}');
  }

  /// POST /api/v1/cooler-sessions/ack
  ///
  /// Tells vms-cloud the kiosk claimed this session so it is not re-sent.
  static Future<void> acknowledgeCoolerSession({
    required String orderId,
    required String sessionId,
  }) async {
    final url = Uri.parse('$_baseUrl/cooler-sessions/ack');
    final response = await http
        .post(
          url,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'machine_no': _machineNo,
            'order_id': orderId,
            'session_id': sessionId,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 404) return;
    throw Exception('Ack failed: ${response.statusCode}');
  }

  /// POST /api/v1/cooler-sessions (multipart)
  ///
  /// Uploads host + sub camera MP4s after the customer closes the door.
  static Future<void> uploadCoolerSession({
    required String orderId,
    required String sessionId,
    required String hostVideoPath,
    required String subVideoPath,
  }) async {
    final url = Uri.parse('$_baseUrl/cooler-sessions');
    final request = http.MultipartRequest('POST', url)
      ..fields['machine_no'] = _machineNo
      ..fields['order_id'] = orderId
      ..fields['session_id'] = sessionId
      ..files.add(await http.MultipartFile.fromPath(
        'host_video',
        hostVideoPath,
        filename: 'host.mp4',
      ))
      ..files.add(await http.MultipartFile.fromPath(
        'sub_video',
        subVideoPath,
        filename: 'sub.mp4',
      ));

    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    final body = _tryDecode(response.body);
    throw Exception(
      body?['message']?.toString() ??
          'Upload failed (${response.statusCode}).',
    );
  }

  /// POST /api/v1/cooler-sessions/failed
  static Future<void> reportCoolerSessionFailure({
    required String orderId,
    required String sessionId,
    required String error,
  }) async {
    final url = Uri.parse('$_baseUrl/cooler-sessions/failed');
    try {
      await http
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'machine_no': _machineNo,
              'order_id': orderId,
              'session_id': sessionId,
              'error': error,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Best-effort.
    }
  }

  /// GET /api/v1/orders/{orderId}
  ///
  /// Poll until status is `completed`, `failed`, or `cancelled`.
  static Future<CoolerOrderStatus> fetchOrderStatus(String orderId) async {
    final url = Uri.parse('$_baseUrl/orders/$orderId');

    final response = await http
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return CoolerOrderStatus.fromJson(body);
    }

    throw Exception('Order status error: ${response.statusCode}');
  }
}

/// Cloud order response for a retail purchase.
class PurchaseOrderResult {
  final String orderId;
  final bool paymentVerified;
  final int? lineNumber;
  final String? paymentMethod;
  final String? message;

  const PurchaseOrderResult({
    required this.orderId,
    required this.paymentVerified,
    this.lineNumber,
    this.paymentMethod,
    this.message,
  });
}

class PurchaseOrderException implements Exception {
  final String message;
  const PurchaseOrderException(this.message);
  @override
  String toString() => message;
}

/// Customer-facing error from a scratch-card lookup.
class LotteryCodeException implements Exception {
  final String message;
  const LotteryCodeException(this.message);
  @override
  String toString() => message;
}
