import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/machine_slot.dart';
import '../theme/vmfs_brand_colors.dart';
import '../utils/tap_feedback.dart';
import 'tap_scale.dart';

/// Modern cloud-styled product tile for the shop grid.
class GridProductCard extends StatelessWidget {
  final MachineSlot slot;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const GridProductCard({
    super.key,
    required this.slot,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final soldOut = slot.showSoldOutBadge;
    final canBuy = slot.isPurchasable;

    return TapScale(
      onTap: onTap,
      child: DecoratedBox(
        decoration: VmfsBrandColors.productCardDecoration(context, soldOut: soldOut),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 13,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ProductImage(slot: slot, cs: cs, primary: primary),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 72,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (slot.productCategory != null &&
                        slot.productCategory!.trim().isNotEmpty)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Text(
                              slot.productCategory!,
                              style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Text(
                        slot.priceFormatted,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (canBuy)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: cs.surface,
                          elevation: 4,
                          shadowColor: primary.withValues(alpha: 0.35),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              TapFeedback.play();
                              onAdd();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: Icon(Icons.add_rounded, color: primary, size: 24),
                            ),
                          ),
                        ),
                      ),
                    if (soldOut)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.58),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white70),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Sold out',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 10,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (slot.productBrand != null &&
                          slot.productBrand!.isNotEmpty)
                        Text(
                          slot.productBrand!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: primary.withValues(alpha: 0.8),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        slot.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            size: 14,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Tap for details',
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.45),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (slot.currentStock > 0 && slot.currentStock <= 3)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${slot.currentStock} left',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final MachineSlot slot;
  final ColorScheme cs;
  final Color primary;

  const _ProductImage({
    required this.slot,
    required this.cs,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final url = slot.productImage;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => DecoratedBox(
          decoration: BoxDecoration(gradient: VmfsBrandColors.cardShimmer),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primary.withValues(alpha: 0.5),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(gradient: VmfsBrandColors.cardShimmer),
        child: Icon(
          Icons.inventory_2_outlined,
          size: 48,
          color: primary.withValues(alpha: 0.35),
        ),
      );
}
