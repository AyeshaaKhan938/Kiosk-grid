import 'package:flutter/material.dart';

enum DemoGuideDestination {
  none,
  adminSettings,
  setupWizardNetwork,
  setupWizardBackend,
  adminPanelDashboard,
  adminPanelProducts,
  adminPanelInventory,
}

/// One step in the guided machine-setup walkthrough (demo / training mode).
class DemoGuideStep {
  const DemoGuideStep({
    required this.id,
    required this.title,
    required this.summary,
    required this.bullets,
    required this.icon,
    this.destination = DemoGuideDestination.none,
    this.coilOnlyNote = false,
  });

  final String id;
  final String title;
  final String summary;
  final List<String> bullets;
  final IconData icon;
  final DemoGuideDestination destination;

  /// Highlights coil / TCN content (not elevator lift calibration).
  final bool coilOnlyNote;

  static List<DemoGuideStep> allSteps({required bool isCoilMachine}) {
    final coilCalibration = isCoilMachine
        ? DemoGuideStep(
            id: 'coil_cal',
            title: 'Coil calibration (coil machines only)',
            summary:
                'For spiral / coil boards, use test vend and coil query — not lift platform calibration.',
            icon: Icons.settings_input_component_rounded,
            coilOnlyNote: true,
            destination: DemoGuideDestination.adminSettings,
            bullets: [
              'Admin Settings → DISPENSE HARDWARE → confirm protocol is '
                  'Reyeah elevator (UART) or TCN serial for coil motors.',
              'Use Test Dispense Slot with an empty coil to verify the motor '
                  'turns and product path is clear.',
              'TCN boards: open TCN SERIAL / COIL → Query coils to read board status.',
              'Do not use Calibrate Lift Platform on coil-only machines — that '
                  'step is for elevator / multi-floor VMC units.',
            ],
          )
        : DemoGuideStep(
            id: 'coil_cal',
            title: 'Coil test vend (this demo unit)',
            summary:
                'This kiosk is configured as an AI cooler or non-coil path. '
                'Skip lift/coil motor steps unless you change hardware protocol.',
            icon: Icons.info_outline_rounded,
            bullets: [
              'Coil calibration and Test Dispense Slot apply to UART / TCN coil machines.',
              'Change DISPENSE HARDWARE in Admin Settings if you attach a coil board.',
            ],
          );

    return [
      const DemoGuideStep(
        id: 'welcome',
        title: 'Welcome to Demo Mode',
        summary:
            'Watch the intro video, then walk through how operators set up a VMFS kiosk.',
        icon: Icons.play_circle_outline_rounded,
        bullets: [
          'Demo mode turns on simulated dispense — no real motor commands.',
          'Cloud calls still work if Wi‑Fi is connected; use a test machine number in the field.',
          'Exit demo anytime from the idle screen or this guide.',
        ],
      ),
      const DemoGuideStep(
        id: 'wifi',
        title: 'Connect Wi‑Fi',
        summary: 'The tablet must reach the internet before cloud sync and updates.',
        icon: Icons.wifi_rounded,
        destination: DemoGuideDestination.setupWizardNetwork,
        bullets: [
          'First install: complete the Setup Wizard → Network step → Open Wi‑Fi Settings.',
          'Already configured: Admin Settings → Exit kiosk mode (temporary) → Android Wi‑Fi.',
          'Ethernet works too — verify with the connectivity check in the setup wizard.',
        ],
      ),
      const DemoGuideStep(
        id: 'cloud',
        title: 'Connect to VMFS Cloud',
        summary: 'Link this tablet to your machine record in vms-cloud.',
        icon: Icons.cloud_outlined,
        destination: DemoGuideDestination.setupWizardBackend,
        bullets: [
          'Setup Wizard → Backend step: enter API URL and tap Test.',
          'On the same screen, paste the activation code from vms-cloud → Machines.',
          'Admin Settings later: Management Token unlocks the Admin Panel tabs.',
          'Default production URL: https://cloud.vmfsusa.com/api/v1',
        ],
      ),
      const DemoGuideStep(
        id: 'admin_access',
        title: 'Open Admin Settings (hidden gesture)',
        summary: 'Operators use a secret tap pattern plus PIN — not shown to customers.',
        icon: Icons.lock_outline_rounded,
        destination: DemoGuideDestination.adminSettings,
        bullets: [
          'On the idle screensaver: tap the top-left corner 5 times within 2 seconds.',
          'On the product browser: tap the VMFS logo in the header 5 times quickly.',
          'Enter the admin PIN (set during setup wizard).',
          'You land on Admin Settings — hardware, cloud, updates, and test vend live here.',
        ],
      ),
      const DemoGuideStep(
        id: 'admin_panel',
        title: 'Admin Panel (dashboard)',
        summary:
            'Day-to-day catalog, stock, and orders — inside Admin Settings → Admin Panel.',
        icon: Icons.dashboard_customize_outlined,
        destination: DemoGuideDestination.adminPanelDashboard,
        bullets: [
          'Requires a valid Management Token in Admin Settings.',
          'Bottom tabs: Dashboard, Inventory, Orders, Products, Ads.',
          'Works offline with local cache; changes sync when the kiosk is online.',
        ],
      ),
      const DemoGuideStep(
        id: 'products',
        title: 'Add products',
        summary: 'Build the catalog customers see on the touchscreen.',
        icon: Icons.storefront_outlined,
        destination: DemoGuideDestination.adminPanelProducts,
        bullets: [
          'Admin Panel → Products → + Add product.',
          'Enter name, SKU, category, and default price.',
          'Save — the product is available to assign to machine slots.',
          'You can also manage products in vms-cloud admin for multi-machine fleets.',
        ],
      ),
      const DemoGuideStep(
        id: 'inventory',
        title: 'Inventory, pricing & slots',
        summary: 'Assign products to slots and set stock levels / prices.',
        icon: Icons.inventory_2_outlined,
        destination: DemoGuideDestination.adminPanelInventory,
        bullets: [
          'Admin Panel → Inventory lists every slot on this machine.',
          'Tap a slot → assign product, set current stock, max stock, and slot price.',
          'Mark slot active; clear fault flag after fixing a jam.',
          'Restock all sets every slot to max capacity in one action.',
        ],
      ),
      const DemoGuideStep(
        id: 'updates',
        title: 'Check for app updates',
        summary: 'Keep the kiosk APK current from vms-cloud releases.',
        icon: Icons.system_update_alt_rounded,
        destination: DemoGuideDestination.adminSettings,
        bullets: [
          'Admin Settings → Auto-update ON for silent OTA installs (recommended).',
          'Manual: Check for Updates downloads the latest APK from cloud.',
          'Idle screen shows a badge when an update is waiting — tap and enter PIN.',
          'Use Exit kiosk mode if Android blocks install permissions.',
        ],
      ),
      coilCalibration,
      const DemoGuideStep(
        id: 'faults',
        title: 'Reset hardware faults',
        summary: 'Clear latched motor or sensor faults after fixing the machine.',
        icon: Icons.healing_outlined,
        destination: DemoGuideDestination.adminSettings,
        bullets: [
          'Reyeah UART: Admin Settings → Clear Board Faults (command 0xA2).',
          'TCN serial: Clear TCN Elevator Fault sends the configured clear-fault string.',
          'In Admin Panel → Inventory, turn off is_fault on a slot after restocking.',
          'Re-run Test Dispense Slot to confirm the coil path is clear.',
        ],
      ),
    ];
  }
}
