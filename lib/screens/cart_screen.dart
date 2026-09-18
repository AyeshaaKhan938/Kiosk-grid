import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import '../services/cart_service.dart';
import '../services/purchase_service.dart';
import '../utils/kiosk_page_transitions.dart';
import '../widgets/kiosk_interactive.dart';
import 'payment_screen.dart';

/// Shopping cart review + checkout.
class CartScreen extends StatefulWidget {
  final String? ageVerificationSessionId;

  const CartScreen({super.key, this.ageVerificationSessionId});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cart = CartService.instance;
  String _error = '';

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;

    final items = List<CartItem>.from(_cart.items);
    final total = items.fold<double>(
      0,
      (sum, item) => sum + (item.slot.price * item.quantity),
    );
    final summary = items.length == 1
        ? items.first.slot.productName
        : '${items.length} items';

    if (!mounted) return;
    Navigator.push(
      context,
      kioskSlideRoute(
        builder: (_) => PaymentScreen(
          amount: total,
          summary: summary,
          completePurchase: (receipt) async {
            final results = await PurchaseService.checkoutCart(
              items,
              ageVerificationSessionId: widget.ageVerificationSessionId,
              payment: receipt,
            );
            _cart.clear();
            return results;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
        listenable: _cart,
        builder: (context, _) {
          if (_cart.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 64, color: cs.onSurface.withValues(alpha: 0.25)),
                  const SizedBox(height: 16),
                  Text('Your cart is empty',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontSize: 16)),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cart.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) =>
                      _CartLine(item: _cart.items[i], cart: _cart),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                      top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface)),
                        Text('\$${_cart.subtotal.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: cs.primary)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: KioskElevatedButton(
                        onPressed: _checkout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Buy',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  final CartItem item;
  final CartService cart;

  const _CartLine({required this.item, required this.cart});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slot = item.slot;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Slot #${slot.lineNumber} · ${slot.priceFormatted}',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.55),
                        fontSize: 13)),
              ],
            ),
          ),
          KioskIconButton(
            onPressed: () => cart.remove(slot.lineNumber),
            icon: Icon(Icons.delete_outline_rounded,
                color: cs.error.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}
