/// Pending cooler session from vms-cloud after POS payment is verified.
class PendingCoolerSession {
  final String orderId;
  final String sessionId;
  final bool paymentVerified;
  final double? amountAuthorized;

  const PendingCoolerSession({
    required this.orderId,
    required this.sessionId,
    required this.paymentVerified,
    this.amountAuthorized,
  });

  factory PendingCoolerSession.fromJson(Map<String, dynamic> json) {
    return PendingCoolerSession(
      orderId: json['order_id']?.toString() ??
          json['orderId']?.toString() ??
          '',
      sessionId: json['session_id']?.toString() ??
          json['sessionId']?.toString() ??
          '',
      paymentVerified: json['payment_verified'] == true ||
          json['paymentVerified'] == true,
      amountAuthorized: _parseDouble(
        json['amount_authorized'] ?? json['amountAuthorized'],
      ),
    );
  }

  static double? _parseDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// Order status polled after videos are uploaded for AI / operator review.
class CoolerOrderStatus {
  final String orderId;
  final String status;
  final String? message;
  final double? finalAmount;

  const CoolerOrderStatus({
    required this.orderId,
    required this.status,
    this.message,
    this.finalAmount,
  });

  bool get isTerminal =>
      status == 'completed' ||
      status == 'failed' ||
      status == 'cancelled' ||
      status == 'canceled';

  bool get isSuccess => status == 'completed';

  factory CoolerOrderStatus.fromJson(Map<String, dynamic> json) {
    return CoolerOrderStatus(
      orderId: json['order_id']?.toString() ??
          json['id']?.toString() ??
          '',
      status: json['status']?.toString() ?? 'unknown',
      message: json['message']?.toString(),
      finalAmount: PendingCoolerSession._parseDouble(
        json['final_amount'] ?? json['finalAmount'] ?? json['amount'],
      ),
    );
  }
}
