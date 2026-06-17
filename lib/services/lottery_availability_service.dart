import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Snapshot of "is the lottery currently runnable on this machine"
/// from vms-cloud. Returned by [LotteryAvailabilityService.check].
class LotteryAvailability {
  final bool available;
  final int inStockCount;
  final int totalCapacity;
  final bool isFailOpen;

  const LotteryAvailability({
    required this.available,
    required this.inStockCount,
    this.totalCapacity = 0,
    this.isFailOpen = false,
  });

  /// If the backend is unreachable, do not overwrite the last known stock.
  const LotteryAvailability.failOpen()
      : available = true,
        inStockCount = 0,
        totalCapacity = 0,
        isFailOpen = true;
}

/// Lightweight check the lottery-code screen runs on init to decide
/// whether to show the code-entry keypad or an "out of stock" card.
///
/// Endpoint: GET /api/v1/machines/{machineNo}/lottery-availability
/// Response: { "available": bool, "in_stock_count": int, "total_capacity"?: int }
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
        final total = (body['total_capacity'] as num?)?.toInt() ??
            (body['max_in_stock_count'] as num?)?.toInt() ??
            (body['total_in_stock_capacity'] as num?)?.toInt() ??
            0;
        return LotteryAvailability(
          available: body['available'] == true,
          inStockCount: (body['in_stock_count'] as num?)?.toInt() ?? 0,
          totalCapacity: total,
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
