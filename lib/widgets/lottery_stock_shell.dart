import 'package:flutter/material.dart';

import '../screens/lottery_out_of_stock_screen.dart';
import '../services/lottery_stock_service.dart';

/// Wraps lottery customer screens with live cloud stock badge and
/// automatic out-of-stock overlay when vms-cloud reports no prizes.
class LotteryStockShell extends StatefulWidget {
  final Widget child;
  const LotteryStockShell({super.key, required this.child});

  @override
  State<LotteryStockShell> createState() => _LotteryStockShellState();
}

class _LotteryStockShellState extends State<LotteryStockShell> {
  final _stock = LotteryStockService.instance;

  @override
  void initState() {
    super.initState();
    _stock.addListener(_onStockChanged);
    _stock.refresh();
  }

  @override
  void dispose() {
    _stock.removeListener(_onStockChanged);
    super.dispose();
  }

  void _onStockChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_stock.isOutOfStock)
          const Positioned.fill(child: LotteryOutOfStockScreen()),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 14,
          child: _StockBadge(label: _stock.stockLabel),
        ),
      ],
    );
  }
}

class _StockBadge extends StatelessWidget {
  final String label;
  const _StockBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
