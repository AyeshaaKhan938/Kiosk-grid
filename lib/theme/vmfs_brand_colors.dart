import 'package:flutter/material.dart';

/// VMFS cloud / portal palette (matches vms-cloud Filament primary).
abstract final class VmfsBrandColors {
  static const Color cloudPrimary = Color(0xFF007ACC);

  static const Color cloudPrimaryDark = Color(0xFF123456);

  static const Color cloudNavy = Color(0xFF0A1628);

  static const Color cloudSurface = Color(0xFFF4F7FB);

  static const Color cloudSurfaceAlt = Color(0xFFE8EEF5);

  static const Color cloudBorder = Color(0xFFD8E2EC);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cloudNavy, cloudPrimaryDark],
  );

  static const LinearGradient cardShimmer = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FAFC), Color(0xFFEEF3F8)],
  );

  /// Customer action buttons (Add, Cart) — cloud blue.
  static Color actionBackground(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static BoxDecoration productCardDecoration(BuildContext context, {bool soldOut = false}) {
    final primary = Theme.of(context).colorScheme.primary;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(
        color: soldOut
            ? VmfsBrandColors.cloudBorder
            : primary.withValues(alpha: 0.18),
        width: 1.2,
      ),
      boxShadow: soldOut
          ? null
          : [
              BoxShadow(
                color: primary.withValues(alpha: 0.14),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }
}
