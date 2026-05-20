import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import '../services/app_config.dart';
import '../services/kiosk_lockdown.dart';
import '../services/reyeah_service.dart';
import '../services/vending_machine_service.dart';
import 'setup_wizard_screen.dart';
import 'admin/admin_shell_screen.dart';

/// Panel de administración oculto — accesible vía gesto secreto + PIN.
///
/// Cómo acceder (desde ProductBrowserScreen):
///   → Toca el logo "VMFS" 5 veces rápido en el header
///   → Ingresa el PIN de admin
///   → Accedes a esta pantalla
///
/// Desde aquí puedes:
///   - Editar la configuración (Machine No, API URL, Lottery Token, PIN)
///   - Ver la configuración actual
///   - Resetear a valores de fábrica
class AdminConfigScreen extends StatefulWidget {
  const AdminConfigScreen({super.key});

  @override
  State<AdminConfigScreen> createState() => _AdminConfigScreenState();
}

class _AdminConfigScreenState extends State<AdminConfigScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.settings_outlined, color: Color(0xFF007ACC), size: 20),
            SizedBox(width: 10),
            Text(
              'Admin Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
            label: const Text('Close',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Admin Panel entry ──────────────────────────────────────────
          _buildAction(
            icon: Icons.admin_panel_settings_rounded,
            label: 'Admin Panel',
            subtitle: AppConfig.managementToken.isNotEmpty
                ? 'Dashboard, inventory, orders & lotteries'
                : 'Requires Management Token — set it below',
            color: AppConfig.managementToken.isNotEmpty
                ? const Color(0xFF7C3AED)
                : Colors.grey,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminShellScreen()),
            ),
          ),
          const SizedBox(height: 20),

          // Sección: Config actual
          _buildInfoCard(),
          const SizedBox(height: 20),

          // ── Backend mode selector ──────────────────────────────────────
          _buildSectionLabel('BACKEND MODE'),
          const SizedBox(height: 10),
          _buildBackendModeSelector(),
          const SizedBox(height: 20),

          // ── Reyeah credentials (solo cuando mode == reyeah) ───────────
          if (AppConfig.backendMode == 'reyeah') ...[
            _buildSectionLabel('REYEAH CLOUD CREDENTIALS'),
            const SizedBox(height: 10),
            _ReyeahCredentialsPanel(onSaved: () => setState(() {})),
            const SizedBox(height: 20),
          ],

          // Sección: Acciones vms-cloud (solo cuando mode == vmscloud)
          if (AppConfig.backendMode == 'vmscloud') ...[
            _buildAction(
              icon: Icons.edit_outlined,
              label: 'Edit Configuration',
              subtitle: 'Change API URL, Machine No., Admin PIN',
              color: const Color(0xFF007ACC),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SetupWizardScreen(isEditing: true),
                  ),
                );
                setState(() {}); // refrescar valores mostrados
              },
            ),
            const SizedBox(height: 12),
          ],

          // ── Management Token (Admin Panel) ────────────────────────────
          _buildSectionLabel('MANAGEMENT TOKEN'),
          const SizedBox(height: 4),
          const Text(
            'Required to unlock the Admin Panel (dashboard, inventory, orders).',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          _ManagementTokenPanel(onSaved: () => setState(() {})),
          const SizedBox(height: 20),

          // ── Lottery Token (botón de sorteo) ───────────────────────────
          _buildSectionLabel('LOTTERY'),
          const SizedBox(height: 4),
          const Text(
            'Optional — enables the lottery draw button for customers.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          _LotteryTokenPanel(onSaved: () => setState(() {})),
          const SizedBox(height: 20),

          // ── Toggle: Simulate Dispense ──────────────────────────────────
          _buildSimulateToggle(),
          const SizedBox(height: 12),

          // ── Test USB connection ────────────────────────────────────────
          _buildAction(
            icon: Icons.usb_rounded,
            label: 'Test USB Serial',
            subtitle: 'Send Device ID request to the Control Board',
            color: const Color(0xFF00BCD4),
            onTap: _testUsb,
          ),
          const SizedBox(height: 12),

          // ── Test Dispense Slot (fires real motor) ──────────────────────
          _buildAction(
            icon: Icons.local_shipping_rounded,
            label: 'Test Dispense Slot',
            subtitle: 'Fire a motor to verify hardware. No order created, no Ten Point Media validation.',
            color: const Color(0xFF4CAF50),
            onTap: _promptTestDispense,
          ),
          const SizedBox(height: 12),

          // ── List USB Devices (debug — identify the connected USB chip) ──
          _buildAction(
            icon: Icons.device_hub_rounded,
            label: 'List USB Devices',
            subtitle: 'Show every USB device attached, with vendor/product IDs. Use this when "not a serial device" errors appear.',
            color: const Color(0xFF9C27B0),
            onTap: _listUsbDevices,
          ),
          const SizedBox(height: 12),

          // ── Exit Kiosk Mode (unlock device for maintenance) ────────────
          _buildAction(
            icon: Icons.lock_open_rounded,
            label: 'Exit Kiosk Mode',
            subtitle: 'Unlock the tablet so you can update the app or access Settings. Re-locks on next app launch.',
            color: const Color(0xFFFFB300),
            onTap: _confirmExitKioskMode,
          ),
          const SizedBox(height: 12),

          _buildAction(
            icon: Icons.restart_alt_rounded,
            label: 'Reset to Factory Defaults',
            subtitle: 'Clears all saved settings. App will show Setup on next launch.',
            color: Colors.redAccent,
            onTap: _confirmReset,
          ),

          const SizedBox(height: 32),
          const Center(
            child: Text(
              'VMFS USA © 2026 — Admin Panel',
              style: TextStyle(color: Colors.white12, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF007ACC),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }

  // ── Backend mode selector ─────────────────────────────────────────────────

  Widget _buildBackendModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF007ACC).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _buildModeOption(
            value:    'vmscloud',
            label:    'vms-cloud (Laravel)',
            subtitle: 'VMFS own backend — lottery, products & dispatch',
            icon:     Icons.dns_outlined,
            color:    const Color(0xFF007ACC),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          _buildModeOption(
            value:    'reyeah',
            label:    'Reyeah Cloud',
            subtitle: 'Direct Reyeah Cloud API — product catalog & orders',
            icon:     Icons.cloud_outlined,
            color:    const Color(0xFF00BCD4),
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required String value,
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final selected = AppConfig.backendMode == value;
    return InkWell(
      onTap: () async {
        await AppConfig.setBackendMode(value);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: selected ? 0.18 : 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: selected ? color : Colors.white38, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        color: selected ? color : Colors.white60,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? color : Colors.transparent,
                border: Border.all(
                  color: selected ? color : Colors.white24,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 12)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Simulate Dispense toggle ──────────────────────────────────────────────

  Widget _buildSimulateToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.science_outlined,
                color: Color(0xFFFF9800), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Simulate Dispense',
                    style: TextStyle(
                        color: Color(0xFFFF9800),
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  AppConfig.simulateDispense
                      ? 'ON — USB serial bypassed (testing mode)'
                      : 'OFF — Real USB serial (production)',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: AppConfig.simulateDispense,
            activeThumbColor: const Color(0xFFFF9800),
            activeTrackColor: const Color(0xFFFF9800).withValues(alpha: 0.4),
            onChanged: (val) async {
              await AppConfig.setSimulateDispense(val);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // ── USB Test ──────────────────────────────────────────────────────────────

  Future<void> _testUsb() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.usb_rounded, color: Color(0xFF00BCD4)),
            SizedBox(width: 10),
            Text('USB Serial Test',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: FutureBuilder<String>(
          future: _runUsbTest(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Row(
                children: [
                  CircularProgressIndicator(
                      color: Color(0xFF00BCD4), strokeWidth: 2),
                  SizedBox(width: 16),
                  Text('Sending ping to VMC…',
                      style: TextStyle(color: Colors.white54)),
                ],
              );
            }
            final ok = snap.data?.startsWith('OK') ?? false;
            return Row(
              children: [
                Icon(
                  ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: ok ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(snap.data ?? 'Unknown error',
                      style: TextStyle(
                          color: ok ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 13)),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF007ACC))),
          ),
        ],
      ),
    );
  }

  // ── Test Dispense Slot ────────────────────────────────────────────────────

  Future<void> _promptTestDispense() async {
    final ctrl = TextEditingController();

    final slotNumber = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.local_shipping_rounded, color: Color(0xFF4CAF50)),
            SizedBox(width: 10),
            Text('Test Dispense Slot',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the slot number (1-99) you want to test. The motor for '
              'that slot will fire — a product will physically drop.\n\n'
              'This bypasses Ten Point Media validation and does NOT create '
              'an order or decrement stock in vms-cloud.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, letterSpacing: 4),
              decoration: InputDecoration(
                hintText: 'Slot #',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF060E18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF4CAF50), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              if (n == null || n < 1 || n > 99) {
                Navigator.pop(context, null);
                return;
              }
              Navigator.pop(context, n);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Fire motor'),
          ),
        ],
      ),
    );

    if (slotNumber == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.local_shipping_rounded, color: Color(0xFF4CAF50)),
            const SizedBox(width: 10),
            Text('Dispensing slot $slotNumber…',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: FutureBuilder<DispenseResult>(
          future: VendingMachineService.testDispenseSlot(slotNumber),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Row(
                children: [
                  CircularProgressIndicator(
                      color: Color(0xFF4CAF50), strokeWidth: 2),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Sending UART delivery command. Watch the machine — '
                      'this can take up to 25 seconds while the motor '
                      'completes its turn.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              );
            }

            final result = snap.data;
            final ok = result?.status == DispenseStatus.success;
            return Row(
              children: [
                Icon(
                  ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: ok ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ok
                        ? 'Success — slot $slotNumber dispensed.'
                        : 'Failed: ${result?.errorMessage ?? "Unknown error"}',
                    style: TextStyle(
                        color: ok ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 13),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF007ACC))),
          ),
        ],
      ),
    );
  }

  // ── List USB Devices (debug) ──────────────────────────────────────────────

  Future<void> _listUsbDevices() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.device_hub_rounded, color: Color(0xFF9C27B0)),
            SizedBox(width: 10),
            Text('USB Devices',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: FutureBuilder<List<UsbDevice>>(
          future: UsbSerial.listDevices(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                width: 280,
                child: Row(children: [
                  CircularProgressIndicator(
                      color: Color(0xFF9C27B0), strokeWidth: 2),
                  SizedBox(width: 16),
                  Text('Scanning…',
                      style: TextStyle(color: Colors.white54)),
                ]),
              );
            }

            if (snap.hasError) {
              return SizedBox(
                width: 320,
                child: Text('Error: ${snap.error}',
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12)),
              );
            }

            final devices = snap.data ?? const <UsbDevice>[];
            if (devices.isEmpty) {
              return const SizedBox(
                width: 320,
                child: Text(
                  'No USB devices detected.\n\nCheck the cable between the '
                  'tablet and the Reyeah board. The tablet must support USB '
                  'OTG host mode and be properly powered.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              );
            }

            return SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Found ${devices.length} device(s):',
                        style: const TextStyle(
                            color: Colors.greenAccent, fontSize: 13)),
                    const SizedBox(height: 12),
                    for (final d in devices) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF060E18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF9C27B0)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: SelectableText(
                          [
                            'Device: ${d.deviceName}',
                            'Product:  ${d.productName ?? "—"}',
                            'Maker:    ${d.manufacturerName ?? "—"}',
                            'Serial:   ${d.serial ?? "—"}',
                            'VID:      0x${(d.vid ?? 0).toRadixString(16).toUpperCase().padLeft(4, "0")}  (${d.vid})',
                            'PID:      0x${(d.pid ?? 0).toRadixString(16).toUpperCase().padLeft(4, "0")}  (${d.pid})',
                            'DeviceId: ${d.deviceId}',
                          ].join('\n'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF007ACC))),
          ),
        ],
      ),
    );
  }

  // ── USB Test helper ───────────────────────────────────────────────────────

  Future<String> _runUsbTest() async {
    try {
      final devices = await UsbSerial.listDevices();
      if (devices.isEmpty) return 'ERROR: No USB serial device found.';
      final device = devices.first;
      final port = await device.create();
      if (port == null) return 'ERROR: Could not open port.';
      await port.open();
      await port.setPortParameters(
          9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      // Send Get Device ID frame
      await port.write(VendingMachineService.buildDeliveryFrame(0));
      await Future.delayed(const Duration(milliseconds: 800));
      await port.close();
      return 'OK — Device connected: ${device.productName ?? device.deviceName}';
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  // ── Info card ────────────────────────────────────────────────────────────

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF007ACC).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CURRENT CONFIGURATION',
            style: TextStyle(
              color: Color(0xFF007ACC),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          _infoRow('Backend Mode',
              AppConfig.backendMode == 'reyeah' ? 'Reyeah Cloud' : 'vms-cloud'),
          if (AppConfig.backendMode == 'reyeah') ...[
            _infoRow('Reyeah Machine', AppConfig.vmMachineNo),
            _infoRow('App ID',
                AppConfig.vmAppId.isNotEmpty
                    ? '${AppConfig.vmAppId.substring(0, AppConfig.vmAppId.length.clamp(0, 8))}…'
                    : '—'),
          ] else ...[
            _infoRow('Machine No.', AppConfig.machineNo),
            _infoRow('API URL', AppConfig.apiBaseUrl),
            _infoRow(
              'Mgmt Token',
              AppConfig.managementToken.isNotEmpty
                  ? '${AppConfig.managementToken.substring(0, 8)}…'
                  : '— not set',
            ),
            _infoRow(
              'Lottery Token',
              AppConfig.lotteryToken.isNotEmpty
                  ? '${AppConfig.lotteryToken.substring(0, 8)}…'
                  : '— disabled',
            ),
          ],
          _infoRow('Admin PIN', '••••'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '— not set —' : value,
              style: TextStyle(
                color: value.isEmpty ? Colors.white24 : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action tile ──────────────────────────────────────────────────────────

  Widget _buildAction({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1A2B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  // ── Exit Kiosk Mode ──────────────────────────────────────────────────────

  Future<void> _confirmExitKioskMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_open_rounded, color: Color(0xFFFFB300)),
            SizedBox(width: 8),
            Text('Exit Kiosk Mode?',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This unpins the screen so you can press Home/Recents, install '
          'updates, or access Android Settings. The app will re-lock the '
          'screen the next time it launches.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlock',
                style: TextStyle(
                    color: Color(0xFFFFB300), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await KioskLockdown.exitKioskMode();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Kiosk mode disabled. You can now access Android.'
            : 'Could not exit kiosk mode (already unlocked or not supported on this device).'),
        backgroundColor: ok ? const Color(0xFF388E3C) : Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Reset ────────────────────────────────────────────────────────────────

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Reset settings?',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will erase all saved configuration. '
          'The app will show the Setup screen on next launch.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset',
                style: TextStyle(color: Colors.redAccent,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AppConfig.clear();
      if (mounted) Navigator.pop(context); // cerrar admin panel
    }
  }
}

// ── Reyeah Credentials Panel ──────────────────────────────────────────────────

/// Formulario embebido para configurar las credenciales de Reyeah Cloud.
/// Se muestra solo cuando backendMode == 'reyeah'.
// ─────────────────────────────────────────────────────────────────────────────
// Lottery / Management Token panel
// ─────────────────────────────────────────────────────────────────────────────

class _LotteryTokenPanel extends StatefulWidget {
  final VoidCallback onSaved;
  const _LotteryTokenPanel({required this.onSaved});

  @override
  State<_LotteryTokenPanel> createState() => _LotteryTokenPanelState();
}

class _LotteryTokenPanelState extends State<_LotteryTokenPanel> {
  late final TextEditingController _ctrl;
  bool _saving   = false;
  bool _obscure  = true;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: AppConfig.lotteryToken);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _saved = null; });
    await AppConfig.setLotteryToken(_ctrl.text);
    if (mounted) {
      setState(() { _saving = false; _saved = 'Saved'; });
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasToken = AppConfig.lotteryToken.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasToken
              ? const Color(0xFF007ACC).withValues(alpha: 0.5)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              hasToken ? Icons.confirmation_num_rounded : Icons.confirmation_num_outlined,
              color: hasToken ? Colors.greenAccent : Colors.white38,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasToken
                    ? 'Lottery button enabled for customers'
                    : 'Lottery disabled — enter token to show the draw button',
                style: TextStyle(
                  color: hasToken ? Colors.greenAccent : Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white, fontSize: 13,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Lottery draw token (per-lottery)',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF060E18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38, size: 16,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) => setState(() => _saved = null),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007ACC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : Text(_saved ?? 'Save',
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Find it in vms-cloud → Lotteries → Token.\n'
            'Each lottery campaign has its own draw token.',
            style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.5),
          ),
          if (_ctrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                _ctrl.clear();
                _save();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
              ),
              child: const Text('Disable lottery draw button (clear token)',
                  style: TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Management Token Panel (Admin Panel access)
// ─────────────────────────────────────────────────────────────────────────────

class _ManagementTokenPanel extends StatefulWidget {
  final VoidCallback onSaved;
  const _ManagementTokenPanel({required this.onSaved});

  @override
  State<_ManagementTokenPanel> createState() => _ManagementTokenPanelState();
}

class _ManagementTokenPanelState extends State<_ManagementTokenPanel> {
  late final TextEditingController _ctrl;
  bool _saving  = false;
  bool _obscure = true;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: AppConfig.managementToken);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _saved = null; });
    await AppConfig.setManagementToken(_ctrl.text);
    if (mounted) {
      setState(() { _saving = false; _saved = 'Saved'; });
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasToken = AppConfig.managementToken.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasToken
              ? const Color(0xFF7C3AED).withValues(alpha: 0.5)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              hasToken ? Icons.admin_panel_settings_rounded : Icons.warning_amber_rounded,
              color: hasToken ? const Color(0xFF7C3AED) : Colors.orange,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasToken
                    ? 'Admin Panel unlocked'
                    : 'Admin Panel locked — enter token to enable',
                style: TextStyle(
                  color: hasToken ? Colors.white70 : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white, fontSize: 13,
                    fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Management API Bearer token',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF060E18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38, size: 16,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) => setState(() => _saved = null),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : Text(_saved ?? 'Save',
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Find it in vms-cloud → Settings → MANAGEMENT_TOKEN.\n'
            'This token has nothing to do with lottery.',
            style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.5),
          ),
          if (_ctrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                _ctrl.clear();
                _save();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
              ),
              child: const Text('Lock Admin Panel (clear token)',
                  style: TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reyeah credentials panel
// ─────────────────────────────────────────────────────────────────────────────

class _ReyeahCredentialsPanel extends StatefulWidget {
  final VoidCallback onSaved;
  const _ReyeahCredentialsPanel({required this.onSaved});

  @override
  State<_ReyeahCredentialsPanel> createState() =>
      _ReyeahCredentialsPanelState();
}

class _ReyeahCredentialsPanelState extends State<_ReyeahCredentialsPanel> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _appIdCtrl;
  late final TextEditingController _appSecretCtrl;
  late final TextEditingController _machineNoCtrl;

  bool _obscureSecret = true;
  bool _saving        = false;
  bool _testing       = false;
  String? _testResult;
  bool _testOk        = false;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl   = TextEditingController(text: AppConfig.vmBaseUrl);
    _appIdCtrl     = TextEditingController(text: AppConfig.vmAppId);
    _appSecretCtrl = TextEditingController(text: AppConfig.vmAppSecret);
    _machineNoCtrl = TextEditingController(text: AppConfig.vmMachineNo);
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _appIdCtrl.dispose();
    _appSecretCtrl.dispose();
    _machineNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AppConfig.saveReyeah(
      baseUrl:   _baseUrlCtrl.text,
      appId:     _appIdCtrl.text,
      appSecret: _appSecretCtrl.text,
      machineNo: _machineNoCtrl.text,
    );
    setState(() => _saving = false);
    widget.onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reyeah credentials saved.'),
          backgroundColor: Color(0xFF007ACC),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; });
    // Save first, then test
    await AppConfig.saveReyeah(
      baseUrl:   _baseUrlCtrl.text,
      appId:     _appIdCtrl.text,
      appSecret: _appSecretCtrl.text,
      machineNo: _machineNoCtrl.text,
    );
    final err = await ReyeahService.testCredentials();
    if (mounted) {
      setState(() {
        _testing    = false;
        _testOk     = err == null;
        _testResult = err ?? 'Connected successfully!';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _credField('Base URL', _baseUrlCtrl,
              hint: 'https://4020y425z1.uicp.fun',
              icon: Icons.link_rounded),
          const SizedBox(height: 12),
          _credField('App ID', _appIdCtrl,
              hint: 'your_app_id',
              icon: Icons.badge_outlined),
          const SizedBox(height: 12),
          _credField('App Secret', _appSecretCtrl,
              hint: '••••••••',
              icon: Icons.key_outlined,
              obscure: _obscureSecret,
              onToggleObscure: () =>
                  setState(() => _obscureSecret = !_obscureSecret)),
          const SizedBox(height: 12),
          _credField('Machine No.', _machineNoCtrl,
              hint: 'e.g. 866903255700003',
              icon: Icons.devices_outlined),
          const SizedBox(height: 16),

          // Test result banner
          if (_testResult != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (_testOk ? Colors.green : Colors.redAccent)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_testOk ? Colors.greenAccent : Colors.redAccent)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testOk
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: _testOk ? Colors.greenAccent : Colors.redAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testOk ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Action buttons
          Row(
            children: [
              // Test
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_testing || _saving) ? null : _test,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00BCD4),
                    side: BorderSide(
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF00BCD4)),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 16),
                  label: Text(_testing ? 'Testing…' : 'Test'),
                ),
              ),
              const SizedBox(width: 12),
              // Save
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_testing || _saving) ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BCD4),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _credField(
    String label,
    TextEditingController ctrl, {
    required String hint,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            prefixIcon: Icon(icon, color: Colors.white38, size: 18),
            suffixIcon: onToggleObscure != null
                ? IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38,
                      size: 18,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF060E18),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                  color: Color(0xFF00BCD4), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ── PIN Dialog ────────────────────────────────────────────────────────────────

/// Muestra el diálogo de PIN y, si es correcto, abre [AdminConfigScreen].
/// Llama esto desde el gesto secreto en cualquier pantalla.
Future<void> showAdminPinDialog(BuildContext context) async {
  final controller = TextEditingController();
  String? error;

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFF007ACC), size: 22),
            SizedBox(width: 10),
            Text('Admin Access',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your admin PIN to access settings.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              maxLength: 8,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••',
                hintStyle: const TextStyle(color: Colors.white24),
                errorText: error,
                errorStyle: const TextStyle(color: Colors.redAccent),
                filled: true,
                fillColor: const Color(0xFF060E18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF007ACC), width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Colors.redAccent),
                ),
              ),
              onSubmitted: (_) => _checkPin(
                  ctx, controller.text, (e) => setDialogState(() => error = e)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => _checkPin(
                ctx, controller.text, (e) => setDialogState(() => error = e)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007ACC),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Enter'),
          ),
        ],
      ),
    ),
  );
}

void _checkPin(
  BuildContext ctx,
  String entered,
  void Function(String?) setError,
) {
  if (entered.trim() == AppConfig.adminPin) {
    Navigator.pop(ctx); // cerrar dialog
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => const AdminConfigScreen()),
    );
  } else {
    setError('Incorrect PIN');
  }
}
