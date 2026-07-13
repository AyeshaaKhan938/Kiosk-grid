import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../models/machine_slot.dart';

/// In-memory cart for the current kiosk session.
class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, i) => sum + i.quantity);

  double get subtotal =>
      _items.fold(0.0, (sum, i) => sum + i.lineTotal);

  bool get isEmpty => _items.isEmpty;

  void add(MachineSlot slot, {int quantity = 1}) {
    if (!slot.isAvailable || slot.isOutOfStock) return;

    CartItem? existing;
    for (final i in _items) {
      if (i.slot.lineNumber == slot.lineNumber) {
        existing = i;
        break;
      }
    }

    if (existing != null) {
      existing.quantity =
          (existing.quantity + quantity).clamp(1, existing.maxQuantity);
    } else {
      _items.add(CartItem(
        slot: slot,
        quantity: quantity.clamp(1, slot.currentStock > 0 ? slot.currentStock : 1),
      ));
    }
    notifyListeners();
  }

  void setQuantity(int lineNumber, int quantity) {
    final idx = _items.indexWhere((i) => i.slot.lineNumber == lineNumber);
    if (idx < 0) return;
    if (quantity <= 0) {
      _items.removeAt(idx);
    } else {
      _items[idx].quantity =
          quantity.clamp(1, _items[idx].maxQuantity);
    }
    notifyListeners();
  }

  void remove(int lineNumber) {
    _items.removeWhere((i) => i.slot.lineNumber == lineNumber);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
