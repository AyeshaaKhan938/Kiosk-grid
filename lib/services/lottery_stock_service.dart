import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lottery_availability_service.dart';

/// Live lottery prize stock from vms-cloud (not a local counter).
///
/// Polls [LotteryAvailabilityService] so customer screens stay in sync with
/// backend inventory. Restocking happens in Admin → Inventory.
class LotteryStockService extends ChangeNotifier {
  LotteryStockService._();
  static final LotteryStockService instance = LotteryStockService._();

  Timer? _pollTimer;
  bool _loadedFromCloud = false;
  bool _available = true;
  int _inStock = 0;
  int _totalCapacity = 0;

  bool get isOutOfStock =>
      _loadedFromCloud && (!_available || _inStock <= 0);

  /// e.g. "12/50" when the API reports capacity; otherwise "12".
  String get stockLabel {
    if (!_loadedFromCloud) return '—';
    if (_totalCapacity > 0) return '$_inStock/$_totalCapacity';
    return '$_inStock';
  }

  static Future<void> init() async {
    await instance.refresh();
    instance._pollTimer?.cancel();
    instance._pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => instance.refresh(),
    );
  }

  /// Pull latest lottery stock from vms-cloud.
  Future<void> refresh() async {
    final snapshot = await LotteryAvailabilityService.check();
    if (snapshot.isFailOpen) return;

    _loadedFromCloud = true;
    _available = snapshot.available;
    _inStock = snapshot.inStockCount;
    _totalCapacity = snapshot.totalCapacity;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
