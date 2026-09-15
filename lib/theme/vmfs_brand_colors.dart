import 'package:flutter/material.dart';

/// VMFS cloud / portal palette (matches vms-cloud Filament primary).
abstract final class VmfsBrandColors {
  static const Color cloudPrimary = Color(0xFF007ACC);

  static const Color cloudPrimaryDark = Color(0xFF123456);

  static const Color cloudNavy = Color(0xFF0A1628);

  /// Customer action buttons (Add, Cart) — use cloud blue, not legacy orange.
  static Color actionBackground(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
}
