import '../models/cart_item.dart';
import '../models/machine_slot.dart';
import '../models/payment_receipt.dart';
import 'api_service.dart';
import 'app_config.dart';
import 'reyeah_service.dart';

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

/// Creates a cloud order after local payment succeeds, then the motor fires.
class PurchaseService {
  /// Single-item checkout (Buy Now from detail or one cart line).
  static Future<PurchaseResult> checkoutItem(
    MachineSlot slot, {
    String? ageVerificationSessionId,
    PaymentReceipt? payment,
  }) async {
    if (!slot.isPurchasable) {
      throw const PurchaseException('This product is out of stock.');
    }

    if (payment == null) {
      throw const PurchaseException(
        'Payment is required before vending.',
      );
    }

    if (AppConfig.backendMode == 'reyeah') {
      return _checkoutReyeah(slot, payment);
    }
    return _checkoutVmsCloud(slot, ageVerificationSessionId, payment);
  }

  /// Multi-item cart — one order + dispense per line (typical vending pattern).
  static Future<List<PurchaseResult>> checkoutCart(
    List<CartItem> items, {
    String? ageVerificationSessionId,
    PaymentReceipt? payment,
  }) async {
    if (items.isEmpty) {
      throw const PurchaseException('Your cart is empty.');
    }
    if (payment == null) {
      throw const PurchaseException(
        'Payment is required before vending.',
      );
    }

    final results = <PurchaseResult>[];
    for (final item in items) {
      for (var i = 0; i < item.quantity; i++) {
        results.add(await checkoutItem(
          item.slot,
          ageVerificationSessionId: ageVerificationSessionId,
          payment: payment,
        ));
      }
    }
    return results;
  }

  static Future<PurchaseResult> _checkoutReyeah(
    MachineSlot slot,
    PaymentReceipt payment,
  ) async {
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
      paymentMethod: payment.method,
    );
  }

  static Future<PurchaseResult> _checkoutVmsCloud(
    MachineSlot slot,
    String? ageVerificationSessionId,
    PaymentReceipt payment,
  ) async {
    try {
      final order = await ApiService.createPurchaseOrder(
        lineNumber: slot.lineNumber,
        amount: slot.price,
        productName: slot.productName,
        ageVerificationSessionId: ageVerificationSessionId,
        paymentMethod: payment.method,
        paymentReference: payment.reference,
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
        paymentMethod: payment.method,
      );
    } on PurchaseOrderException catch (e) {
      throw PurchaseException(e.message);
    }
  }
}
