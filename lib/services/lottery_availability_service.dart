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
/// Source of truth: the machine's live slot inventory.
///   GET /api/v1/machines/{machineNo}/slots
///
/// A dedicated GET /machines/{machineNo}/lottery-availability endpoint was
/// originally planned, but the deployed backend never shipped it (it returns
/// 404 "route could not be found"). That 404 made every poll fail open, so the
/// stock badge was stuck on "—" and never tracked live inventory. We now
/// derive availability by aggregating the slots endpoint, which IS live, while
/// still preferring the dedicated endpoint automatically if it ever ships.
class LotteryAvailabilityService {
  LotteryAvailabilityService._();

  static Future<LotteryAvailability> check() async {
    final dedicated = await _checkDedicatedEndpoint();
    if (dedicated != null) return dedicated;
    return _checkFromSlots();
  }

  /// Try the (currently non-existent) dedicated availability endpoint.
  ///   - 200            → parse and return the snapshot
  ///   - 404            → route not deployed; return null so the caller falls
  ///                      back to aggregating /slots
  ///   - other / error  → backend is reachable-but-unhappy or the network is
  ///                      down; return a fail-open snapshot so we don't wipe
  ///                      the last known stock
  static Future<LotteryAvailability?> _checkDedicatedEndpoint() async {
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

      if (r.statusCode == 404) {
        // Route not deployed — fall back to the slots endpoint.
        return null;
      }

      debugPrint('[availability] HTTP ${r.statusCode}, failing open');
      return const LotteryAvailability.failOpen();
    } catch (e) {
      debugPrint('[availability] dedicated check failed: $e — failing open');
      return const LotteryAvailability.failOpen();
    }
  }

  /// Derive availability from the live slot inventory:
  ///   GET /api/v1/machines/{machineNo}/slots
  ///
  /// in_stock_count = Σ current_stock over slots that are enabled and not
  /// faulted; total_capacity = Σ max_stock over those same slots.
  static Future<LotteryAvailability> _checkFromSlots() async {
    final url = Uri.parse(
      '${AppConfig.apiBaseUrl}/machines/${AppConfig.machineNo}/slots',
    );
    try {
      final r = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final slots = (body['slots'] as List?) ?? const [];

        int inStock = 0;
        int capacity = 0;
        for (final s in slots.cast<Map<String, dynamic>>()) {
          final available = s['is_available'] as bool? ?? false;
          final fault = s['is_fault'] as bool? ?? false;
          if (!available || fault) continue;
          inStock += (s['current_stock'] as num?)?.toInt() ?? 0;
          capacity += (s['max_stock'] as num?)?.toInt() ?? 0;
        }

        return LotteryAvailability(
          available: inStock > 0,
          inStockCount: inStock,
          totalCapacity: capacity,
        );
      }

      debugPrint('[availability] slots HTTP ${r.statusCode}, failing open');
      return const LotteryAvailability.failOpen();
    } catch (e) {
      debugPrint('[availability] slots check failed: $e — failing open');
      return const LotteryAvailability.failOpen();
    }
  }
}
