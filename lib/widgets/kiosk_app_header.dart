import 'package:flutter/material.dart';
import '../services/cart_service.dart';

/// Consistent dark gradient header used across kiosk customer screens.
class KioskAppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onLogoTap;
  final VoidCallback? onRefresh;
  final VoidCallback? onCart;

  const KioskAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.onLogoTap,
    this.onRefresh,
    this.onCart,
  });

  static double sidePad(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w > 900) return 32;
    if (w > 600) return 24;
    return 16;
  }

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 520;

  @override
  Widget build(BuildContext context) {
    final pad = sidePad(context);
    final compact = isCompact(context);
    const iconConstraints = BoxConstraints(minWidth: 40, minHeight: 40);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A1628), Color(0xFF123456)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
          child: Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white.withValues(alpha: 0.9), size: 20),
                  padding: EdgeInsets.zero,
                  constraints: iconConstraints,
                ),
                SizedBox(width: compact ? 2 : 4),
              ],
              GestureDetector(
                onTap: onLogoTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/vmfs-logo.jpg',
                    height: compact ? 34 : 40,
                    width: compact ? 34 : 40,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!compact &&
                        subtitle != null &&
                        subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRefresh != null)
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: onRefresh,
                      padding: EdgeInsets.zero,
                      constraints: iconConstraints,
                      icon: Icon(Icons.refresh_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: compact ? 20 : 22),
                    ),
                  if (onCart != null) _CartHeaderButton(onTap: onCart!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartHeaderButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CartHeaderButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final count = CartService.instance.itemCount;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Cart',
              onPressed: onTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: Icon(Icons.shopping_cart_outlined,
                  color: Colors.white.withValues(alpha: 0.9), size: 24),
            ),
            if (count > 0)
              Positioned(
                right: 4,
                top: 4,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bottom-left cart shortcut for narrow / mobile layouts.
class MobileCartFab extends StatelessWidget {
  final VoidCallback onTap;

  const MobileCartFab({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!KioskAppHeader.isCompact(context)) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final count = CartService.instance.itemCount;
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: FloatingActionButton.extended(
            heroTag: 'mobile_cart_fab',
            backgroundColor: const Color(0xFFFF6B35),
            foregroundColor: Colors.white,
            onPressed: onTap,
            icon: const Icon(Icons.shopping_cart_outlined),
            label: Text(count > 0 ? 'Cart ($count)' : 'Cart'),
          ),
        );
      },
    );
  }
}
