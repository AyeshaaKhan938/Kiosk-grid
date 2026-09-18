import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/payment_receipt.dart';
import '../services/app_config.dart';
import '../services/payment_terminal_service.dart';
import '../services/purchase_service.dart';
import '../utils/kiosk_page_transitions.dart';
import 'purchase_result_screen.dart';

/// Collect card or cash payment, then complete the purchase + vend.
class PaymentScreen extends StatefulWidget {
  final double amount;
  final String summary;
  final Future<List<PurchaseResult>> Function(PaymentReceipt receipt)
      completePurchase;

  const PaymentScreen({
    super.key,
    required this.amount,
    required this.summary,
    required this.completePurchase,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _terminal = PaymentTerminalService.instance;
  StreamSubscription<PaymentEvent>? _sub;

  PaymentPhase _phase = PaymentPhase.chooseMethod;
  String _status = '';
  String _error = '';
  bool _completing = false;
  double _cashIn = 0;
  String _activeMethod = 'card';

  @override
  void initState() {
    super.initState();
    _sub = _terminal.events.listen(_onEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_terminal.cancel());
    super.dispose();
  }

  void _bootstrap() {
    final card = AppConfig.paymentCardEnabled;
    final cash = AppConfig.paymentCashEnabled;
    if (!card && !cash) {
      unawaited(_startCard());
      return;
    }
    if (card && !cash) {
      unawaited(_startCard());
    } else if (cash && !card) {
      unawaited(_startCash());
    } else {
      setState(() => _phase = PaymentPhase.chooseMethod);
    }
  }

  void _onEvent(PaymentEvent event) {
    if (!mounted || _completing) return;

    switch (event.type) {
      case 'credit':
        setState(() {
          _cashIn = (event.amountCents ?? 0) / 100.0;
          _status =
              'Inserted \$${_cashIn.toStringAsFixed(2)} of \$${widget.amount.toStringAsFixed(2)}';
        });
        break;
      case 'success':
        unawaited(_finish(PaymentReceipt(
          method: _activeMethod,
          provider: event.provider ??
              (_activeMethod == 'cash'
                  ? 'cash'
                  : AppConfig.effectiveCardProvider),
          reference: event.reference ??
              'PAY-${DateTime.now().millisecondsSinceEpoch}',
          amountPaid: widget.amount,
        )));
        break;
      case 'declined':
        setState(() {
          _phase = PaymentPhase.failed;
          _error = event.message ?? 'Payment declined. Try again.';
        });
        break;
      case 'error':
        setState(() {
          _phase = PaymentPhase.failed;
          _error = event.message ?? 'Payment device error.';
        });
        break;
      case 'cancelled':
        break;
      case 'status':
        setState(() => _status = event.message ?? _status);
        break;
    }
  }

  Future<void> _startCard() async {
    setState(() {
      _activeMethod = 'card';
      _phase = PaymentPhase.waitingCard;
      _error = '';
      _status = AppConfig.shouldSimulatePayment
          ? 'Simulating card approval…'
          : 'Tap or insert card on the ${AppConfig.paymentCardProviderLabel} reader';
    });
    SemanticsService.announce(_status, TextDirection.ltr);
    await _terminal.startCardPayment(amountDollars: widget.amount);
  }

  Future<void> _startCash() async {
    setState(() {
      _activeMethod = 'cash';
      _phase = PaymentPhase.waitingCash;
      _error = '';
      _cashIn = 0;
      _status =
          'Insert bills or coins — \$${widget.amount.toStringAsFixed(2)} due';
    });
    SemanticsService.announce(_status, TextDirection.ltr);
    await _terminal.startCashPayment(amountDollars: widget.amount);
  }

  Future<void> _finish(PaymentReceipt receipt) async {
    if (_completing) return;
    setState(() {
      _completing = true;
      _phase = PaymentPhase.authorizing;
      _status = 'Payment approved — starting vend…';
    });

    try {
      final purchases = await widget.completePurchase(receipt);
      if (!mounted) return;
      if (purchases.isEmpty) {
        setState(() {
          _completing = false;
          _phase = PaymentPhase.failed;
          _error = 'Payment captured but order failed.';
        });
        return;
      }
      Navigator.of(context).pushReplacement(
        kioskSlideRoute(
          builder: (_) => PurchaseResultScreen(purchases: purchases),
        ),
      );
    } on PurchaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _phase = PaymentPhase.failed;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _phase = PaymentPhase.failed;
        _error = 'Payment ok, but order failed. Contact staff.';
      });
    }
  }

  Future<void> _cancel() async {
    await _terminal.cancel();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _completing ? null : _cancel,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cancel',
                  ),
                  const Spacer(),
                  Text(
                    'Payment',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.summary,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '\$${widget.amount.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(child: _buildBody(cs)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_phase == PaymentPhase.chooseMethod) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'How would you like to pay?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 28),
          if (AppConfig.paymentCardEnabled)
            _methodButton(
              cs: cs,
              icon: Icons.credit_card_rounded,
              label: 'Card',
              subtitle: AppConfig.shouldSimulatePayment
                  ? 'Reader simulation'
                  : AppConfig.paymentCardProviderLabel,
              onTap: _startCard,
            ),
          if (AppConfig.paymentCardEnabled && AppConfig.paymentCashEnabled)
            const SizedBox(height: 16),
          if (AppConfig.paymentCashEnabled)
            _methodButton(
              cs: cs,
              icon: Icons.payments_rounded,
              label: 'Cash',
              subtitle: 'Bills & coins',
              onTap: _startCash,
            ),
        ],
      );
    }

    if (_phase == PaymentPhase.failed) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 72, color: cs.error),
          const SizedBox(height: 16),
          Text(
            _error,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: cs.onSurface),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () {
              setState(() {
                _phase = PaymentPhase.chooseMethod;
                _error = '';
              });
            },
            child: const Text('Try again'),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_phase == PaymentPhase.waitingCard)
          Icon(Icons.contactless_rounded, size: 88, color: cs.primary)
        else if (_phase == PaymentPhase.waitingCash)
          Icon(Icons.payments_outlined, size: 88, color: cs.primary)
        else
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(color: cs.primary, strokeWidth: 3),
          ),
        const SizedBox(height: 24),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            height: 1.35,
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_phase == PaymentPhase.waitingCash) ...[
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: widget.amount <= 0
                  ? 1
                  : (_cashIn / widget.amount).clamp(0.0, 1.0),
              minHeight: 14,
            ),
          ),
          if (AppConfig.cashSimulateButtons) ...[
            const SizedBox(height: 24),
            Text(
              'Test cash inserts',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final dollars in [1.0, 5.0, 10.0])
                  OutlinedButton(
                    onPressed: () =>
                        _terminal.addSimulatedCashCredit(dollars),
                    child: Text('\$${dollars.toStringAsFixed(0)}'),
                  ),
              ],
            ),
          ],
        ],
        if (_phase == PaymentPhase.waitingCard &&
            AppConfig.shouldSimulatePayment) ...[
          const SizedBox(height: 20),
          Text(
            'Demo mode — approving shortly…',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontSize: 14,
            ),
          ),
        ],
        if (_phase == PaymentPhase.waitingCard &&
            !AppConfig.shouldSimulatePayment) ...[
          const SizedBox(height: 20),
          Text(
            'Use the ${AppConfig.paymentCardProviderLabel} card reader',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontSize: 14,
            ),
          ),
        ],
        const SizedBox(height: 36),
        if (!_completing)
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel payment'),
          ),
      ],
    );
  }

  Widget _methodButton({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            child: Row(
              children: [
                Icon(icon, size: 36, color: cs.primary),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurface),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
