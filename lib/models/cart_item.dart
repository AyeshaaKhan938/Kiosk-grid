import 'machine_slot.dart';

/// One line in the shopping cart — tied to a physical vending slot.
class CartItem {
  final MachineSlot slot;
  int quantity;

  CartItem({required this.slot, this.quantity = 1});

  double get lineTotal => slot.price * quantity;

  /// Vending slots typically hold one unit; cap at available stock.
  int get maxQuantity =>
      slot.currentStock > 0 ? slot.currentStock : 1;
}
