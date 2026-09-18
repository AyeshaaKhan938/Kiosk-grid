import 'dart:async';

import 'package:flutter/services.dart';

import '../models/payment_receipt.dart';
import 'app_config.dart';

/// Talks to Contaloupe / Nayax card readers and bill/coin acceptors.
///
/// Real OEM SDKs plug into the Android [PaymentChannel]. Until then:
/// - provider `simulate` (or Simulate Payment ON) completes in-app
/// - `nayax` / `contaloupe` wait for native/EventChannel success
/// - cash waits until inserted credit >= amount (simulate can add credit)
class PaymentTerminalService {
  PaymentTerminalService._();
  static final PaymentTerminalService instance = PaymentTerminalService._();

  static const _methods = MethodChannel('vmfs.kiosk/payment');
  static const _events = EventChannel('vmfs.kiosk/payment_events');

  StreamSubscription<dynamic>? _eventSub;
  final _controller = StreamController<PaymentEvent>.broadcast();

  Stream<PaymentEvent> get events => _controller.stream;

  bool _sessionActive = false;
  double _cashCreditCents = 0;
  double _targetCents = 0;
  String _method = 'card';
  String _provider = 'simulate';

  double get cashCreditDollars => _cashCreditCents / 100.0;
  double get targetDollars => _targetCents / 100.0;
  bool get sessionActive => _sessionActive;

  Future<void> ensureListening() async {
    if (_eventSub != null) return;
    _eventSub = _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        final map = Map<String, dynamic>.from(raw);
        final event = PaymentEvent(
          type: map['type']?.toString() ?? 'status',
          message: map['message']?.toString(),
          amountCents: (map['amount_cents'] as num?)?.toDouble(),
          reference: map['reference']?.toString(),
          provider: map['provider']?.toString(),
        );
        _handleNativeEvent(event);
      },
      onError: (Object e) {
        _controller.add(PaymentEvent(
          type: 'error',
          message: e.toString(),
        ));
      },
    );
  }

  void _handleNativeEvent(PaymentEvent event) {
    if (!_sessionActive) return;

    if (event.type == 'credit' && event.amountCents != null) {
      _cashCreditCents += event.amountCents!;
      _controller.add(PaymentEvent(
        type: 'credit',
        amountCents: _cashCreditCents,
        message: 'Credit updated',
      ));
      if (_method == 'cash' && _cashCreditCents + 0.5 >= _targetCents) {
        _emitSuccess(
          reference: event.reference ??
              'CASH-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      return;
    }

    if (event.type == 'success') {
      _emitSuccess(
        reference: event.reference ??
            'PAY-${DateTime.now().millisecondsSinceEpoch}',
        provider: event.provider,
      );
      return;
    }

    _controller.add(event);
  }

  Future<void> startCardPayment({required double amountDollars}) async {
    await cancel();
    await ensureListening();

    _sessionActive = true;
    _method = 'card';
    _provider = AppConfig.effectiveCardProvider;
    _targetCents = (amountDollars * 100).roundToDouble();
    _cashCreditCents = 0;

    _controller.add(const PaymentEvent(
      type: 'status',
      message: 'Waiting for card…',
    ));

    if (AppConfig.shouldSimulatePayment) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!_sessionActive || _method != 'card') return;
      _emitSuccess(
        reference: 'SIM-CARD-${DateTime.now().millisecondsSinceEpoch}',
        provider: 'simulate',
      );
      return;
    }

    try {
      await _methods.invokeMethod<void>('startCardPayment', {
        'amount_cents': _targetCents.round(),
        'provider': _provider,
        'currency': 'USD',
      });
    } on PlatformException catch (e) {
      _controller.add(PaymentEvent(
        type: 'error',
        message: e.message ?? 'Card reader unavailable.',
      ));
    } catch (_) {
      _controller.add(const PaymentEvent(
        type: 'error',
        message: 'Card reader unavailable on this device.',
      ));
    }
  }

  Future<void> startCashPayment({required double amountDollars}) async {
    await cancel();
    await ensureListening();

    _sessionActive = true;
    _method = 'cash';
    _provider = 'cash';
    _targetCents = (amountDollars * 100).roundToDouble();
    _cashCreditCents = 0;

    _controller.add(const PaymentEvent(
      type: 'status',
      message: 'Insert bills or coins…',
    ));

    try {
      await _methods.invokeMethod<void>('startCashPayment', {
        'amount_cents': _targetCents.round(),
      });
    } on PlatformException catch (_) {
      // Native bridge optional — simulate cash UI still works.
    } catch (_) {}
  }

  /// Demo / lab: add credit without a physical acceptor.
  void addSimulatedCashCredit(double dollars) {
    if (!_sessionActive || _method != 'cash') return;
    if (!AppConfig.shouldSimulatePayment && !AppConfig.cashSimulateButtons) {
      return;
    }
    final cents = (dollars * 100).roundToDouble();
    _handleNativeEvent(PaymentEvent(
      type: 'credit',
      amountCents: cents,
      reference: 'SIM-CASH-${DateTime.now().millisecondsSinceEpoch}',
    ));
  }

  Future<void> cancel() async {
    final wasActive = _sessionActive;
    _sessionActive = false;
    _cashCreditCents = 0;
    _targetCents = 0;

    if (wasActive) {
      try {
        await _methods.invokeMethod<void>('cancelPayment');
      } catch (_) {}
      _controller.add(const PaymentEvent(type: 'cancelled'));
    }
  }

  void _emitSuccess({required String reference, String? provider}) {
    if (!_sessionActive) return;
    _sessionActive = false;
    final receiptProvider = provider ?? _provider;
    _controller.add(PaymentEvent(
      type: 'success',
      reference: reference,
      provider: receiptProvider,
      amountCents: _targetCents,
      message: 'Payment approved',
    ));
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
  }
}
