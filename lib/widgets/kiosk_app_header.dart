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
    final w = MediaQuery.of(context).size.width;
    if (w > 900) return 32;
    if (w > 600) return 24;
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    final pad = sidePad(context);

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
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 4),
              ],
              GestureDetector(
                onTap: onLogoTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/vmfs-logo.jpg',
                    height: 40,
                    width: 40,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
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
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: onRefresh,
                  icon: Icon(Icons.refresh_rounded,
                      color: Colors.white.withValues(alpha: 0.85), size: 22),
                ),
              if (onCart != null)
                ListenableBuilder(
                  listenable: CartService.instance,
                  builder: (context, _) {
                    final count = CartService.instance.itemCount;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          tooltip: 'Cart',
                          onPressed: onCart,
                          icon: Icon(Icons.shopping_cart_outlined,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 24),
                        ),
                        if (count > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B35),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
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
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
