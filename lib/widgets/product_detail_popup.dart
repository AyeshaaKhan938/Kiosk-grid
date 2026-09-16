import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/machine_slot.dart';
import '../services/cart_service.dart';
import '../services/purchase_service.dart';
import '../utils/kiosk_page_transitions.dart';
import '../utils/tap_feedback.dart';
import '../widgets/kiosk_interactive.dart';
import '../screens/purchase_result_screen.dart';

/// Opens product details as a centered popup (grid shop UX).
Future<void> showProductDetailPopup(
  BuildContext context, {
  required MachineSlot slot,
  String? ageVerificationSessionId,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close product',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Opacity(
        opacity: curved.value,
        child: Transform.scale(
          scale: 0.92 + (0.08 * curved.value),
          child: Center(
            child: _ProductDetailPopupDialog(
              slot: slot,
              ageVerificationSessionId: ageVerificationSessionId,
            ),
          ),
        ),
      );
    },
  );
}

class _ProductDetailPopupDialog extends StatefulWidget {
  final MachineSlot slot;
  final String? ageVerificationSessionId;

  const _ProductDetailPopupDialog({
    required this.slot,
    this.ageVerificationSessionId,
  });

  @override
  State<_ProductDetailPopupDialog> createState() =>
      _ProductDetailPopupDialogState();
}

class _ProductDetailPopupDialogState extends State<_ProductDetailPopupDialog> {
  bool _loading = false;
  String _error = '';

  MachineSlot get slot => widget.slot;

  bool get _soldOut => slot.isOutOfStock || !slot.isAvailable;

  void _addToCart() {
    if (_soldOut) return;
    TapFeedback.play();
    CartService.instance.add(slot);
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  Future<void> _buyNow() async {
    if (_loading || _soldOut) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final result = await PurchaseService.checkoutItem(
        slot,
        ageVerificationSessionId: widget.ageVerificationSessionId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).pushReplacement(
        kioskSlideRoute(
          builder: (_) => PurchaseResultScreen(purchases: [result]),
        ),
      );
    } on PurchaseException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Purchase failed. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxW = size.width > 720 ? 520.0 : size.width * 0.92;
    final maxH = size.height * 0.82;
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: cs.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: maxH * 0.38,
                      width: double.infinity,
                      child: _buildImage(cs, primary),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    if (_soldOut)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.5),
                          alignment: Alignment.center,
                          child: const Text(
                            'Sold out',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (slot.productCategory != null)
                          Text(
                            slot.productCategory!.toUpperCase(),
                            style: TextStyle(
                              color: primary.withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          slot.productName,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (slot.productBrand != null &&
                            slot.productBrand!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            slot.productBrand!,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.55),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              slot.priceFormatted,
                              style: TextStyle(
                                color: primary,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            _InfoPill(
                              icon: Icons.inventory_2_outlined,
                              label: '${slot.currentStock} in stock',
                            ),
                            const SizedBox(width: 8),
                            _InfoPill(
                              icon: Icons.tag,
                              label: 'Slot ${slot.lineNumber}',
                            ),
                          ],
                        ),
                        if (_error.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.errorContainer.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error,
                              style: TextStyle(color: cs.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _soldOut ? null : _addToCart,
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                          label: const Text('Add to cart'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            side: BorderSide(color: primary, width: 1.5),
                            foregroundColor: primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KioskElevatedButton(
                          onPressed: _loading || _soldOut ? null : _buyNow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: cs.onPrimary,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.onPrimary,
                                  ),
                                )
                              : const Text(
                                  'Buy now',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(ColorScheme cs, Color primary) {
    final url = slot.productImage;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: cs.surfaceContainerHighest),
        errorWidget: (_, __, ___) => _placeholder(cs, primary),
      );
    }
    return _placeholder(cs, primary);
  }

  Widget _placeholder(ColorScheme cs, Color primary) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.inventory_2_outlined,
            size: 64, color: primary.withValues(alpha: 0.35)),
      );
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
