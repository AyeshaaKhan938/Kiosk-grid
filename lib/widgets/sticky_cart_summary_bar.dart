import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../services/cart_service.dart';

/// Sticky bottom bar: order summary always visible on the grid shop screen.
class StickyCartSummaryBar extends StatelessWidget {
  final VoidCallback onCheckout;
  final VoidCallback onViewCart;

  const StickyCartSummaryBar({
    super.key,
    required this.onCheckout,
    required this.onViewCart,
  });

  String _formatTotal(double amount) => '\$${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final cart = CartService.instance;
        final hasItems = !cart.isEmpty;
        final items = cart.items;
        final preview = items.take(2).toList();
        final extra = items.length - preview.length;

        return Material(
          elevation: 16,
          shadowColor: Colors.black.withValues(alpha: 0.28),
          color: cs.surface,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primary.withValues(alpha: hasItems ? 0.08 : 0.04),
                    cs.surface,
                  ],
                ),
                border: Border(
                  top: BorderSide(
                    color: primary.withValues(alpha: hasItems ? 0.5 : 0.22),
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Material(
                    color: primary.withValues(alpha: hasItems ? 0.14 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: hasItems ? onViewCart : null,
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_rounded,
                              color: primary.withValues(alpha: hasItems ? 1 : 0.45),
                              size: 26,
                            ),
                            if (hasItems)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${cart.itemCount}',
                                    style: TextStyle(
                                      color: cs.onPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: GestureDetector(
                      onTap: hasItems ? onViewCart : null,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hasItems ? 'Your order' : 'Order summary',
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.55),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (!hasItems)
                            Text(
                              'Tap a product or + to add items',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.65),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else ...[
                            ...preview.map(
                              (CartItem line) => Text(
                                '${line.quantity > 1 ? '${line.quantity}× ' : ''}${line.slot.productName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (extra > 0)
                              Text(
                                '+ $extra more item${extra == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTotal(hasItems ? cart.subtotal : 0),
                        style: TextStyle(
                          color: primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        hasItems
                            ? '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}'
                            : 'Cart empty',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: hasItems ? onCheckout : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: cs.onPrimary,
                      disabledBackgroundColor:
                          cs.onSurface.withValues(alpha: 0.12),
                      disabledForegroundColor:
                          cs.onSurface.withValues(alpha: 0.35),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Checkout',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
