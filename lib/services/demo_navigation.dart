import 'package:flutter/material.dart';

import '../screens/admin/admin_shell_screen.dart';
import '../screens/admin_config_screen.dart';
import '../screens/setup_wizard_screen.dart';
import '../models/demo_guide_step.dart';
import 'app_config.dart';

/// Opens admin-gated destinations from the demo guide.
Future<void> openDemoGuideDestination(
  BuildContext context,
  DemoGuideDestination destination,
) async {
  switch (destination) {
    case DemoGuideDestination.none:
      return;
    case DemoGuideDestination.setupWizardNetwork:
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SetupWizardScreen(isEditing: true),
        ),
      );
      return;
    case DemoGuideDestination.adminSettings:
      await showAdminPinDialog(context);
      return;
    case DemoGuideDestination.adminPanelDashboard:
      await _openAdminPanel(context, initialTab: 0);
      return;
    case DemoGuideDestination.adminPanelProducts:
      await _openAdminPanel(context, initialTab: 3);
      return;
    case DemoGuideDestination.adminPanelInventory:
      await _openAdminPanel(context, initialTab: 1);
      return;
  }
}

Future<void> _openAdminPanel(BuildContext context, {required int initialTab}) async {
  if (AppConfig.managementToken.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Set a Management Token in Admin Settings before opening the Admin Panel.',
        ),
      ),
    );
    await showAdminPinDialog(context);
    return;
  }

  if (!context.mounted) return;

  await showAdminPinDialog(
    context,
    pushAfterPin: (_) => AdminShellScreen(initialTab: initialTab),
  );
}
