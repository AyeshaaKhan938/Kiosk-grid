import 'package:flutter/material.dart';
import '../screens/admin_config_screen.dart';
import '../screens/lottery_out_of_stock_screen.dart';
import '../services/lottery_stock_service.dart';

/// Wraps lottery customer screens with live stock badge, restock control,
/// and automatic out-of-stock overlay.
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
  }

  @override
  void dispose() {
    _stock.removeListener(_onStockChanged);
    super.dispose();
  }

  void _onStockChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onRestock() async {
    final ok = await verifyAdminPin(context);
    if (!ok || !mounted) return;
    // Wait for dialog route to finish closing before rebuilding overlay.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _stock.restock();
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
        Positioned(
          bottom: MediaQuery.paddingOf(context).bottom + 14,
          left: 14,
          child: _RestockButton(onPressed: _onRestock),
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

class _RestockButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _RestockButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'Restock',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
