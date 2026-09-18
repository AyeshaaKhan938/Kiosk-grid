/// Result of a successful terminal / cash payment on the kiosk.
class PaymentReceipt {
  final String method; // card | cash
  final String provider; // nayax | contaloupe | cash | simulate
  final String reference;
  final double amountPaid;

  const PaymentReceipt({
    required this.method,
    required this.provider,
    required this.reference,
    required this.amountPaid,
  });
}

enum PaymentPhase {
  chooseMethod,
  waitingCard,
  waitingCash,
  authorizing,
  success,
  failed,
  cancelled,
}

class PaymentEvent {
  final String type; // credit | success | declined | error | status
  final String? message;
  final double? amountCents;
  final String? reference;
  final String? provider;

  const PaymentEvent({
    required this.type,
    this.message,
    this.amountCents,
    this.reference,
    this.provider,
  });
}
