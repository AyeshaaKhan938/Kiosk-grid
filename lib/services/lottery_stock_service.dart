import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks lottery prize inventory on the kiosk (software-side counter).
class LotteryStockService extends ChangeNotifier {
  LotteryStockService._();
  static final LotteryStockService instance = LotteryStockService._();

  static const _kCurrent = 'lottery_stock_current';
  static const _kFull    = 'lottery_stock_full';

  static const int _defaultFull = 50;

  SharedPreferences? _prefs;
  int _current = _defaultFull;
  int _full    = _defaultFull;

  int get currentStock => _current;
  int get fullStock    => _full;
  bool get isOutOfStock => _current <= 0;
  String get stockLabel => '$_current/$_full';

  static Future<void> init() async {
    final svc = instance;
    svc._prefs = await SharedPreferences.getInstance();

    final envFull = int.tryParse(dotenv.env['LOTTERY_FULL_STOCK'] ?? '');
    svc._full = svc._prefs!.getInt(_kFull) ??
        envFull ??
        _defaultFull;

    final envCurrent = int.tryParse(dotenv.env['LOTTERY_CURRENT_STOCK'] ?? '');
    svc._current = svc._prefs!.getInt(_kCurrent) ??
        envCurrent ??
        svc._full;

    svc._current = svc._current.clamp(0, svc._full);
  }

  /// Award one prize (after successful redemption).
  Future<void> decrement() async {
    if (_current <= 0) return;
    _current--;
    await _prefs?.setInt(_kCurrent, _current);
    notifyListeners();
  }

  /// Admin restock — reset to full capacity.
  Future<void> restock() async {
    _current = _full;
    await _prefs?.setInt(_kCurrent, _current);
    notifyListeners();
  }

  /// Set full capacity (admin / setup).
  Future<void> setFullStock(int value) async {
    if (value < 1) return;
    _full = value;
    if (_current > _full) _current = _full;
    await _prefs?.setInt(_kFull, _full);
    await _prefs?.setInt(_kCurrent, _current);
    notifyListeners();
  }
}
