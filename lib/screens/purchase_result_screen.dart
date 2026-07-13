import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../services/app_config.dart';
import '../services/purchase_service.dart';
import '../services/vending_machine_service.dart';
import 'idle_screen.dart';

/// Post-purchase dispense screen — verifies payment already happened,
/// fires the vend motor for each purchased slot, shows thank-you.
class PurchaseResultScreen extends StatefulWidget {
  final List<PurchaseResult> purchases;

  const PurchaseResultScreen({super.key, required this.purchases});

  @override
  State<PurchaseResultScreen> createState() => _PurchaseResultScreenState();
}

enum _Phase { dispensing, success, partial, error }

class _PurchaseResultScreenState extends State<PurchaseResultScreen> {
  _Phase _phase = _Phase.dispensing;
  String _statusMsg = 'Verifying payment…';
  String _errorMsg = '';
  int _dispensed = 0;
  Timer? _returnTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runDispense());
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    super.dispose();
  }

  Future<void> _runDispense() async {
    final purchases = widget.purchases;
    if (purchases.isEmpty) {
      setState(() {
        _phase = _Phase.error;
        _errorMsg = 'No items to dispense.';
      });
      return;
    }

    var failures = 0;

    for (var i = 0; i < purchases.length; i++) {
      final p = purchases[i];
      if (!mounted) return;

      setState(() {
        _statusMsg = 'Dispensing ${p.slot.productName}… '
            '(${i + 1}/${purchases.length})';
      });

      SemanticsService.announce(_statusMsg, TextDirection.ltr);

      try {
        final result = await VendingMachineService.dispenseProduct(
          lineNumber: p.slot.lineNumber,
          lotteryCode: p.orderId,
          machineNo: AppConfig.machineNo,
          simulateSuccess: AppConfig.simulateDispense,
          paymentMethod: p.paymentMethod,
          paymentReference: p.orderId,
        );

        if (result.status == DispenseStatus.success) {
          _dispensed++;
        } else {
          failures++;
        }
      } catch (_) {
        failures++;
      }
    }

    if (!mounted) return;

    if (failures == 0) {
      SemanticsService.announce(
          'Thank you. Please collect your items below.', TextDirection.ltr);
      setState(() => _phase = _Phase.success);
      _returnTimer = Timer(const Duration(seconds: 8), _goIdle);
    } else if (_dispensed > 0) {
      setState(() {
        _phase = _Phase.partial;
        _errorMsg =
            '$failures item(s) could not be dispensed. $_dispensed succeeded.';
      });
      _returnTimer = Timer(const Duration(seconds: 10), _goIdle);
    } else {
      setState(() {
        _phase = _Phase.error;
        _errorMsg = 'Dispense failed. Please contact staff for a refund.';
      });
    }
  }

  void _goIdle() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const IdleScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildIcon(cs),
                const SizedBox(height: 24),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: cs.onSurface.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),
                if (_phase != _Phase.dispensing) ...[
                  const SizedBox(height: 32),
                  TextButton(onPressed: _goIdle, child: const Text('Done')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.dispensing:
        return 'Please wait';
      case _Phase.success:
        return 'Thank you!';
      case _Phase.partial:
        return 'Partially dispensed';
      case _Phase.error:
        return 'Something went wrong';
    }
  }

  String get _subtitle {
    switch (_phase) {
      case _Phase.dispensing:
        return _statusMsg;
      case _Phase.success:
        return 'Please collect your item${_dispensed > 1 ? 's' : ''} from the tray below.';
      case _Phase.partial:
      case _Phase.error:
        return _errorMsg;
    }
  }

  Widget _buildIcon(ColorScheme cs) {
    switch (_phase) {
      case _Phase.dispensing:
        return SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(color: cs.primary, strokeWidth: 3),
        );
      case _Phase.success:
        return Icon(Icons.check_circle_rounded,
            size: 72, color: Colors.green.shade400);
      case _Phase.partial:
        return Icon(Icons.warning_amber_rounded,
            size: 72, color: Colors.orange.shade400);
      case _Phase.error:
        return Icon(Icons.error_outline_rounded,
            size: 72, color: cs.error);
    }
  }
}
