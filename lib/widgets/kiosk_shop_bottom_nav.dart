import 'package:flutter/material.dart';

import '../services/cart_service.dart';
import '../theme/vmfs_brand_colors.dart';

/// Bottom navigation row — all primary shop actions live here (bottom-heavy UX).
class KioskShopBottomNav extends StatelessWidget {
  final VoidCallback onBackToAds;
  final VoidCallback onOpenCart;
  final VoidCallback? onRefresh;

  const KioskShopBottomNav({
    super.key,
    required this.onBackToAds,
    required this.onOpenCart,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final pad = MediaQuery.paddingOf(context).horizontal > 0 ? 16.0 : 16.0;

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 10),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: VmfsBrandColors.cloudBorder),
          ),
        ),
        child: ListenableBuilder(
        listenable: CartService.instance,
        builder: (context, _) {
          final count = CartService.instance.itemCount;
          return Row(
            children: [
              Expanded(
                child: _NavTile(
                  icon: Icons.slideshow_outlined,
                  label: 'Ads',
                  onTap: onBackToAds,
                  primary: primary,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              if (onRefresh != null) ...[
                Expanded(
                  child: _NavTile(
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    onTap: onRefresh!,
                    primary: primary,
                    cs: cs,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: onRefresh != null ? 1 : 2,
                child: _NavTile(
                  icon: Icons.shopping_bag_outlined,
                  label: count > 0 ? 'Cart ($count)' : 'Cart',
                  onTap: onOpenCart,
                  primary: primary,
                  cs: cs,
                  filled: count > 0,
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

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color primary;
  final ColorScheme cs;
  final bool filled;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
    required this.cs,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? primary.withValues(alpha: 0.12) : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: filled ? primary : cs.onSurface.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: filled ? primary : cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
