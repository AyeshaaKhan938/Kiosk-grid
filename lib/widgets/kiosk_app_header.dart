import 'package:flutter/material.dart';
import '../theme/vmfs_brand_colors.dart';
import 'accessibility_options_panel.dart';
import 'kiosk_interactive.dart';
import 'tap_scale.dart';

/// Consistent dark gradient header used across kiosk customer screens.
class KioskAppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onLogoTap;
  final VoidCallback? onRefresh;
  final bool showAccessibility;

  const KioskAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.onLogoTap,
    this.onRefresh,
    this.showAccessibility = true,
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
        gradient: VmfsBrandColors.headerGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
          child: Row(
            children: [
              if (onBack != null) ...[
                KioskIconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white.withValues(alpha: 0.9), size: 20),
                  padding: EdgeInsets.zero,
                  constraints: iconConstraints,
                ),
                SizedBox(width: compact ? 2 : 4),
              ],
              TapScale(
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
                  if (showAccessibility)
                    KioskIconButton(
                      tooltip: 'Accessibility',
                      onPressed: () => showAccessibilityOptionsSheet(context),
                      padding: EdgeInsets.zero,
                      constraints: iconConstraints,
                      icon: Text(
                        '♿',
                        style: TextStyle(
                          fontSize: compact ? 18 : 20,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  if (onRefresh != null)
                    KioskIconButton(
                      tooltip: 'Refresh',
                      onPressed: onRefresh,
                      padding: EdgeInsets.zero,
                      constraints: iconConstraints,
                      icon: Icon(Icons.refresh_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: compact ? 20 : 22),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
