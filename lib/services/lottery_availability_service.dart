import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Snapshot of "is the lottery currently runnable on this machine"
/// from vms-cloud. Returned by [LotteryAvailabilityService.check].
class LotteryAvailability {
  final bool available;
  final int inStockCount;

  const LotteryAvailability({
    required this.available,
    required this.inStockCount,
  });

  /// "Fail-open" default — if the backend is unreachable or returns an
  /// unexpected response, we report the lottery as available rather than
  /// silently locking the kiosk into out-of-stock mode. A real submission
  /// will still get the proper 503 NO_STOCK error from the backend if
  /// there's actually no stock.
  const LotteryAvailability.failOpen()
      : available = true,
        inStockCount = 0;
}

/// Lightweight check the lottery-code screen runs on init to decide
/// whether to show the code-entry keypad or an "out of stock" card.
///
/// Endpoint: GET /api/v1/machines/{machineNo}/lottery-availability
/// Response: { "available": bool, "in_stock_count": int }
class LotteryAvailabilityService {
  LotteryAvailabilityService._();

  static Future<LotteryAvailability> check() async {
    final url = Uri.parse(
      '${AppConfig.apiBaseUrl}/machines/${AppConfig.machineNo}/lottery-availability',
    );
    try {
      final r = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return LotteryAvailability(
          available: body['available'] == true,
          inStockCount: (body['in_stock_count'] as num?)?.toInt() ?? 0,
        );
      }

      debugPrint('[availability] HTTP ${r.statusCode}, failing open');
      return const LotteryAvailability.failOpen();
    } catch (e) {
      debugPrint('[availability] check failed: $e — failing open');
      return const LotteryAvailability.failOpen();
    }
  }
}
