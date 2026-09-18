import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/machine_slot.dart';
import '../services/cart_service.dart';
import '../services/purchase_service.dart';
import '../theme/vmfs_brand_colors.dart';
import '../utils/kiosk_page_transitions.dart';
import '../utils/tap_feedback.dart';
import '../widgets/kiosk_interactive.dart';
import '../screens/payment_screen.dart';

/// Opens product details as an animated centered popup (grid shop UX).
Future<void> showProductDetailPopup(
  BuildContext context, {
  required MachineSlot slot,
  String? ageVerificationSessionId,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close product details',
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (ctx, _, __) => _ProductDetailPopupDialog(
      slot: slot,
      ageVerificationSessionId: ageVerificationSessionId,
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
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
  late PageController _galleryCtrl;
  int _galleryIndex = 0;

  @override
  void initState() {
    super.initState();
    _galleryCtrl = PageController();
  }

  @override
  void dispose() {
    _galleryCtrl.dispose();
    super.dispose();
  }

  MachineSlot get slot => widget.slot;

  bool get _soldOut => slot.showSoldOutBadge;

  List<String> get _images => slot.allImages;

  void _addToCart() {
    if (_soldOut) return;
    TapFeedback.play();
    CartService.instance.add(slot);
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  Future<void> _buyNow() async {
    if (_loading || _soldOut) return;

    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      kioskSlideRoute(
        builder: (_) => PaymentScreen(
          amount: slot.price,
          summary: slot.productName,
          completePurchase: (receipt) async {
            final result = await PurchaseService.checkoutItem(
              slot,
              ageVerificationSessionId: widget.ageVerificationSessionId,
              payment: receipt,
            );
            return [result];
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxW = size.width > 720 ? 540.0 : size.width * 0.94;
    final maxH = size.height * 0.86;
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final images = _images;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: ColoredBox(
              color: cs.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: maxH * 0.4,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (images.isEmpty)
                          _placeholder(cs, primary)
                        else if (images.length == 1)
                          _image(images.first, cs, primary)
                        else
                          PageView.builder(
                            controller: _galleryCtrl,
                            itemCount: images.length,
                            onPageChanged: (i) => setState(() => _galleryIndex = i),
                            itemBuilder: (_, i) => _image(images[i], cs, primary),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black38, Colors.transparent, Colors.transparent],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.92),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, color: Colors.black87),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                images.length,
                                (i) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _galleryIndex ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: i == _galleryIndex
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_soldOut)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                            child: Center(
                              child: Text(
                                'Sold out',
                                style: TextStyle(
                                  color: cs.onPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (slot.productCategory != null)
                            Text(
                              slot.productCategory!.toUpperCase(),
                              style: TextStyle(
                                color: primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            slot.productName,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          if (slot.productBrand != null &&
                              slot.productBrand!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              slot.productBrand!,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.55),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                slot.priceFormatted,
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              _InfoPill(
                                icon: Icons.inventory_2_outlined,
                                label: '${slot.currentStock} in stock',
                              ),
                              _InfoPill(
                                icon: Icons.tag,
                                label: 'Slot ${slot.lineNumber}',
                              ),
                            ],
                          ),
                          if (slot.productDescription != null &&
                              slot.productDescription!.trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'About',
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.5),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              slot.productDescription!.trim(),
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.78),
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ],
                          if (_error.isNotEmpty) ...[
                            const SizedBox(height: 14),
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    decoration: BoxDecoration(
                      color: VmfsBrandColors.cloudSurface,
                      border: Border(top: BorderSide(color: VmfsBrandColors.cloudBorder)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _soldOut ? null : _addToCart,
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                            label: const Text('Add to cart'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              side: BorderSide(color: primary, width: 1.5),
                              foregroundColor: primary,
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
                              minimumSize: const Size.fromHeight(54),
                              elevation: 0,
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
      ),
    );
  }

  Widget _image(String url, ColorScheme cs, Color primary) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: cs.surfaceContainerHighest),
      errorWidget: (_, __, ___) => _placeholder(cs, primary),
    );
  }

  Widget _placeholder(ColorScheme cs, Color primary) => DecoratedBox(
        decoration: const BoxDecoration(gradient: VmfsBrandColors.cardShimmer),
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
        color: VmfsBrandColors.cloudSurfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VmfsBrandColors.cloudBorder),
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
