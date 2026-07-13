import '../models/cart_item.dart';
import '../models/machine_slot.dart';
import 'api_service.dart';
import 'app_config.dart';
import 'reyeah_service.dart';
import 'afen_vmc_service.dart';

/// Result of a verified purchase ready for physical dispense.
class PurchaseResult {
  final String orderId;
  final MachineSlot slot;
  final double amount;
  final String paymentMethod;

  const PurchaseResult({
    required this.orderId,
    required this.slot,
    required this.amount,
    this.paymentMethod = 'card',
  });
}

class PurchaseException implements Exception {
  final String message;
  const PurchaseException(this.message);
  @override
  String toString() => message;
}

/// Creates a cloud order + verifies payment before the motor fires.
class PurchaseService {
  /// Single-item checkout (Buy Now from detail or one cart line).
  static Future<PurchaseResult> checkoutItem(
    MachineSlot slot, {
    String? ageVerificationSessionId,
  }) async {
    if (!slot.isAvailable || slot.isOutOfStock) {
      throw const PurchaseException('This product is out of stock.');
    }

    if (AppConfig.backendMode == 'reyeah') {
      return _checkoutReyeah(slot);
    }
    if (AppConfig.backendMode == 'afen') {
      return _checkoutAfen(slot);
    }
    return _checkoutVmsCloud(slot, ageVerificationSessionId);
  }

  /// Multi-item cart — one order + dispense per line (typical vending pattern).
  static Future<List<PurchaseResult>> checkoutCart(
    List<CartItem> items, {
    String? ageVerificationSessionId,
  }) async {
    if (items.isEmpty) {
      throw const PurchaseException('Your cart is empty.');
    }

    final results = <PurchaseResult>[];
    for (final item in items) {
      for (var i = 0; i < item.quantity; i++) {
        results.add(await checkoutItem(
          item.slot,
          ageVerificationSessionId: ageVerificationSessionId,
        ));
      }
    }
    return results;
  }

  static Future<PurchaseResult> _checkoutReyeah(MachineSlot slot) async {
    final externalId = slot.externalId;
    if (externalId == null || externalId.isEmpty) {
      throw const PurchaseException(
        'Product is not configured for ordering. Contact support.',
      );
    }

    final orderNo =
        await ReyeahService.createOrder(machineLineProductId: externalId);
    await ReyeahService.shipment(orderNo);

    return PurchaseResult(
      orderId: orderNo,
      slot: slot,
      amount: slot.price,
      paymentMethod: 'reyeah',
    );
  }

  static Future<PurchaseResult> _checkoutAfen(MachineSlot slot) async {
    // AFEN FunCode 8000/9000 payment can be wired later; for now authorize
    // vend via FunCode 2000 and return order id = trade number.
    final tradeNo = DateTime.now().millisecondsSinceEpoch.toString();
    final auth = await AfenVmcService.identifyPassword(
      slotNo: slot.lineNumber,
      price: slot.price.toStringAsFixed(2),
      tradeNo: tradeNo,
    );
    if (auth['Status']?.toString() != '0') {
      throw PurchaseException(
        auth['Err']?.toString() ?? 'AFEN vend authorization failed.',
      );
    }
    return PurchaseResult(
      orderId: tradeNo,
      slot: slot,
      amount: slot.price,
      paymentMethod: 'afen',
    );
  }

  static Future<PurchaseResult> _checkoutVmsCloud(
    MachineSlot slot,
    String? ageVerificationSessionId,
  ) async {
    try {
      final order = await ApiService.createPurchaseOrder(
        lineNumber: slot.lineNumber,
        amount: slot.price,
        productName: slot.productName,
        ageVerificationSessionId: ageVerificationSessionId,
      );

      if (order.paymentVerified != true) {
        throw PurchaseException(
          order.message ?? 'Payment could not be verified.',
        );
      }

      return PurchaseResult(
        orderId: order.orderId,
        slot: slot,
        amount: slot.price,
        paymentMethod: order.paymentMethod ?? 'card',
      );
    } on PurchaseOrderException catch (e) {
      throw PurchaseException(e.message);
    }
  }
}
