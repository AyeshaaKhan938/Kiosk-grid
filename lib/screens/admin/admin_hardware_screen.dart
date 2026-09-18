import 'package:flutter/material.dart';

import '../../models/machine_mechanism.dart';
import '../../services/app_config.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_page_scaffold.dart';
import 'vmc_floor_height_screen.dart';
import 'vmc_log_screen.dart';

/// Hardware tools scoped to the machine's detected delivery mechanism.
class AdminHardwareScreen extends StatelessWidget {
  const AdminHardwareScreen({super.key});

  MachineMechanism get _mechanism => AppConfig.machineMechanism;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AdminSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                switch (_mechanism) {
                  MachineMechanism.elevator => Icons.elevator_outlined,
                  MachineMechanism.coil =>
                    Icons.settings_input_component_outlined,
                  MachineMechanism.conveyor => Icons.view_week_rounded,
                  MachineMechanism.cooler => Icons.kitchen_outlined,
                },
                color: AdminColors.accent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mechanism.label,
                      style: const TextStyle(
                        color: AdminColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Auto-detected from dispense hardware: '
                      '${AppConfig.hardwareProtocolLabel}',
                      style: const TextStyle(
                        color: AdminColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._toolsForMechanism(context),
      ],
    );
  }

  List<Widget> _toolsForMechanism(BuildContext context) {
    switch (_mechanism) {
      case MachineMechanism.elevator:
        return [
          const AdminSectionLabel('ELEVATOR / LIFT'),
          AdminActionTile(
            icon: Icons.article_outlined,
            label: 'Fetch VMC log',
            subtitle:
                'CMD 0x03 on ${AppConfig.ttyPath}, then read diagnostics at 115200.',
            accent: AdminColors.accent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AdminTheme.withLightTheme(child: const VmcLogScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AdminActionTile(
            icon: Icons.vertical_align_top_rounded,
            label: 'Floor heights',
            subtitle:
                'Read and adjust per-floor lift heights (CMD 0x20 / 0x21).',
            accent: const Color(0xFF7C3AED),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminTheme.withLightTheme(
                  child: const VmcFloorHeightScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          AdminSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Port: ${AppConfig.ttyPath} · Commands at 9600 baud unless noted.',
              style: const TextStyle(
                color: AdminColors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ];
      case MachineMechanism.coil:
        return [
          const AdminSectionLabel('COIL / SPIRAL'),
          AdminSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Coil tools live in Admin Settings',
                  style: TextStyle(
                    color: AdminColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use Admin Settings → Test Coil Dispense and '
                  'TCN SERIAL / COIL → Query coils. Lift / VMC tools are hidden '
                  'because this cabinet is coil-only.',
                  style: const TextStyle(
                    color: AdminColors.textSecondary,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'TTY: ${AppConfig.ttyPath}',
                  style: const TextStyle(
                    color: AdminColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ];
      case MachineMechanism.conveyor:
        return [
          const AdminSectionLabel('CONVEYOR'),
          AdminSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Conveyor lane tools',
                  style: TextStyle(
                    color: AdminColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use Admin Settings → Test Conveyor Lane and TTY Serial Port. '
                  'Elevator lift calibration is not shown for belt cabinets.',
                  style: const TextStyle(
                    color: AdminColors.textSecondary,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'TTY: ${AppConfig.ttyPath}',
                  style: const TextStyle(
                    color: AdminColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ];
      case MachineMechanism.cooler:
        return [
          const AdminSectionLabel('AI COOLER'),
          AdminSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cooler session tools',
                  style: TextStyle(
                    color: AdminColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use Admin Settings → Test Unlock Door / Cooler Session. '
                  'No elevator or coil motor tools apply to this cabinet.',
                  style: const TextStyle(
                    color: AdminColors.textSecondary,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ];
    }
  }
}
