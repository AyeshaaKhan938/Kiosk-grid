import 'package:flutter/material.dart';

import '../services/app_config.dart';
import 'cooler_shadow_screen.dart';
import 'idle_screen.dart';

/// Entry screen after setup — slot vending vs AI cooler headless mode.
class KioskHomeScreen extends StatelessWidget {
  const KioskHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.isBketCooler) {
      return const CoolerShadowScreen();
    }
    return const IdleScreen();
  }
}
