import 'dart:async';

import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import '../services/app_config.dart';
import '../services/kiosk_lockdown.dart';
import '../services/reyeah_service.dart';
import '../services/tty_serial.dart';
import '../services/update_service.dart';
import '../services/vending_machine_service.dart';
import '../widgets/onscreen_keypad.dart';
import 'setup_wizard_screen.dart';
import 'admin/admin_logs_screen.dart';
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

          // ── Toggle: Auto-update ────────────────────────────────────────
          _buildAutoUpdateToggle(),
          const SizedBox(height: 12),

          // ── Toggle: Auto-upload logs ───────────────────────────────────
          _buildAutoUploadLogsToggle(),
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

          // ── Reset VMC + Home Lift (CMD 0xA1) — elevator recovery ──────
          _buildAction(
            icon: Icons.home_repair_service_rounded,
            label: 'Reset VMC / Home Lift',
            subtitle: 'Sends CMD 0xA1 to fully reset the Reyeah control '
                'board. On elevator machines this also drives the lift '
                'platform back to its home (bottom) position. Use this '
                'when the lift is parked at the wrong floor and dispenses '
                'silently fail.',
            color: const Color(0xFFEF5350),
            onTap: _resetVmc,
          ),
          const SizedBox(height: 12),

          // ── Clear board faults (CMD 0xA2) — admin recovery ─────────────
          _buildAction(
            icon: Icons.restart_alt_rounded,
            label: 'Clear Board Faults',
            subtitle: 'Sends 0xA2 to reset latched motor / sensor faults '
                'on the Reyeah control board. Use this if a slot stopped '
                'dispensing after an error.',
            color: const Color(0xFFFF7043),
            onTap: _clearBoardFaults,
          ),
          const SizedBox(height: 12),

          // ── Calibrate Lift Platform (elevator machines only) ───────────
          _buildAction(
            icon: Icons.vertical_align_top_rounded,
            label: 'Calibrate Lift Platform',
            subtitle: 'Elevator machines only. Sends CMD 0x21 to teach '
                'the VMC each floor\'s height — the lift will physically '
                'run through every floor (~45 s). Run this once after '
                'switching Machine Type to Elevator; the VMC persists '
                'the result.',
            color: const Color(0xFF8E24AA),
            onTap: _calibrateLift,
          ),
          const SizedBox(height: 12),

          // ── View Logs (field debugging) ────────────────────────────────
          _buildAction(
            icon: Icons.article_outlined,
            label: 'View Logs',
            subtitle: 'Read the persistent log file: every dispense, '
                'TTY operation, heartbeat, and error with timestamps. '
                'Used when troubleshooting field issues.',
            color: const Color(0xFF42A5F5),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminLogsScreen()),
            ),
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

          // ── List TTY Devices + pick the one wired to the motor ─────────
          _buildAction(
            icon: Icons.cable_rounded,
            label: 'TTY Serial Port (main VMC)',
            subtitle: 'Currently: ${AppConfig.ttyPath}. Main UART — dispense, status, clear fault. Tap to pick from available /dev/ttyS* devices.',
            color: const Color(0xFFFF6F00),
            onTap: _pickTtyDevice,
          ),
          const SizedBox(height: 12),

          // Second UART for elevator-capable machines — the lift
          // platform's MCU listens on a separate port (factory.apk's
          // PostUtil.port_forlifter, default /dev/ttyS8). Calibrate
          // commands are routed here.
          _buildAction(
            icon: Icons.swap_calls_rounded,
            label: 'Lift Platform TTY Port (elevator only)',
            subtitle: 'Currently: ${AppConfig.ttyPathLift}. Second UART for the lift platform on T1-02 / T11-PRO / S4 hardware. Calibrate Lift uses this. Tap to override.',
            color: const Color(0xFFAB47BC),
            onTap: _pickLiftTtyDevice,
          ),
          const SizedBox(height: 12),

          // ── Machine Type (coil vs elevator/lift) ───────────────────────
          _buildAction(
            icon: Icons.precision_manufacturing_rounded,
            label: 'Machine Type',
            subtitle: 'Currently: ${_machineTypeLabel(AppConfig.machineType)}. '
                'Coil = traditional spring lane. Elevator = lift-platform machines '
                '(T1-02 / T11-PRO / S4) — uses side-push axis 0xFB on every dispense.',
            color: const Color(0xFF9575CD),
            onTap: _pickMachineType,
          ),
          const SizedBox(height: 12),

          // ── Check for Updates (downloads + installs a new APK from vms-cloud)
          _buildAction(
            icon: Icons.system_update_rounded,
            label: 'Check for Updates',
            subtitle: 'Download and install the latest APK from vms-cloud. Settings + PIN are preserved.',
            color: const Color(0xFF388E3C),
            onTap: _checkForUpdates,
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

  // ── Auto-update toggle ────────────────────────────────────────────────────

  Widget _buildAutoUpdateToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF388E3C).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF388E3C).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_sync_outlined,
                color: Color(0xFF388E3C), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Auto-update',
                    style: TextStyle(
                        color: Color(0xFF388E3C),
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  AppConfig.autoUpdate
                      ? 'ON — new APKs download + install silently (no operator interaction)'
                      : 'OFF — manual updates only via "Check for Updates"',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: AppConfig.autoUpdate,
            activeThumbColor: const Color(0xFF388E3C),
            activeTrackColor: const Color(0xFF388E3C).withValues(alpha: 0.4),
            onChanged: (val) async {
              await AppConfig.setAutoUpdate(val);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  // ── Auto-upload-logs toggle ───────────────────────────────────────────────

  Widget _buildAutoUploadLogsToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF42A5F5).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF42A5F5).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_upload_outlined,
                color: Color(0xFF42A5F5), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Auto-upload logs',
                    style: TextStyle(
                        color: Color(0xFF42A5F5),
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  AppConfig.autoUploadLogs
                      ? 'ON — log files ship to vms-cloud every 6 h (no operator action)'
                      : 'OFF — manual upload only via View Logs → "Send to vms-cloud"',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: AppConfig.autoUploadLogs,
            activeThumbColor: const Color(0xFF42A5F5),
            activeTrackColor: const Color(0xFF42A5F5).withValues(alpha: 0.4),
            onChanged: (val) async {
              await AppConfig.setAutoUploadLogs(val);
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
              readOnly: true,
              showCursor: true,
              enableInteractiveSelection: false,
              keyboardType: TextInputType.number,
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
              onTap: () => showKeypad(
                context,
                controller: ctrl,
                mode: KeypadMode.numeric,
                maxLength: 2,
                title: 'SLOT NUMBER',
                hint: '1 – 99',
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

    // The new progress dialog manages its own lifecycle so it can:
    //  - survive the multi-second UART round-trip without crashing the
    //    admin route (the dialog state lives independently of the
    //    in-flight future),
    //  - show staged progress text ("Sending command" → "Motor turning"
    //    → "Cooling down") instead of a single static placeholder,
    //  - auto-dismiss back to the admin panel on success so the operator
    //    lands on the same screen they came from.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DispenseProgressDialog(slotNumber: slotNumber),
    );
  }

  // ── Calibrate Lift Platform (CMD 0x21 — elevator only) ──────────────────

  Future<void> _calibrateLift() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.vertical_align_top_rounded, color: Color(0xFF8E24AA)),
          SizedBox(width: 10),
          Expanded(child: Text('Calibrate Lift Platform',
              style: TextStyle(color: Colors.white, fontSize: 17))),
        ]),
        content: FutureBuilder<DispenseResult>(
          future: VendingMachineService.calibrateLiftViaGate(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                width: 320,
                child: Row(children: [
                  SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Color(0xFF8E24AA), strokeWidth: 2.5)),
                  SizedBox(width: 14),
                  Expanded(child: Text(
                    'Sending CMD 0x21 to the VMC… the lift platform '
                    'will run through every floor while it learns the '
                    'heights. Don\'t open the cabinet door. About 45 s.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  )),
                ]),
              );
            }
            final result = snap.data;
            final ok = result?.status == DispenseStatus.success;
            return SizedBox(
              width: 320,
              child: Row(children: [
                Icon(
                  ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: ok ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  ok
                      ? 'Calibration sent. Wait for the lift to finish its '
                          'travel (if it hasn\'t already) then run Test '
                          'Dispense Slot — the VMC now knows each floor\'s '
                          'height and only needs this calibration once per '
                          'machine.'
                      : 'Failed: ${result?.errorMessage ?? "Unknown error"}',
                  style: TextStyle(
                    color: ok ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 13,
                  ),
                )),
              ]),
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

  // ── Reset VMC / Home lift (CMD 0xA1) ─────────────────────────────────────

  Future<void> _resetVmc() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.home_repair_service_rounded, color: Color(0xFFEF5350)),
          SizedBox(width: 10),
          Expanded(child: Text('Reset VMC / Home Lift',
              style: TextStyle(color: Colors.white, fontSize: 17))),
        ]),
        content: FutureBuilder<DispenseResult>(
          future: VendingMachineService.resetVmcViaGate(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                width: 320,
                child: Row(children: [
                  SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Color(0xFFEF5350), strokeWidth: 2.5)),
                  SizedBox(width: 14),
                  Expanded(child: Text(
                    'Sending CMD 0xA1 reset… the lift platform will '
                    'travel back to its home position. About 10 seconds.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  )),
                ]),
              );
            }
            final result = snap.data;
            final ok = result?.status == DispenseStatus.success;
            return SizedBox(
              width: 320,
              child: Row(children: [
                Icon(
                  ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: ok ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  ok
                      ? 'Reset sent. The lift should now be at its home '
                          'position. Run a Test Dispense to confirm — the '
                          'lift should travel to the slot\'s floor before '
                          'the push axis engages.'
                      : 'Failed: ${result?.errorMessage ?? "Unknown error"}',
                  style: TextStyle(
                    color: ok ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 13,
                  ),
                )),
              ]),
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

  // ── Clear board faults (CMD 0xA2) ─────────────────────────────────────────

  Future<void> _clearBoardFaults() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.restart_alt_rounded, color: Color(0xFFFF7043)),
          SizedBox(width: 10),
          Text('Clear Board Faults',
              style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: FutureBuilder<DispenseResult>(
          future: VendingMachineService.clearFaultsViaGate(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Row(children: [
                SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Color(0xFFFF7043), strokeWidth: 2.5)),
                SizedBox(width: 14),
                Expanded(child: Text(
                  'Sending 0xA2 clear-fault command…',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                )),
              ]);
            }
            final result = snap.data;
            final ok = result?.status == DispenseStatus.success;
            return Row(children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: ok ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(
                ok
                    ? 'Sent. Faults should now be cleared on the board. '
                        'Run a Test Dispense to confirm.'
                    : 'Failed: ${result?.errorMessage ?? "Unknown error"}',
                style: TextStyle(
                  color: ok ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 13,
                ),
              )),
            ]);
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

  // ── Pick TTY Device (set which /dev/ttyS* is the Reyeah motor port) ──────

  Future<void> _pickTtyDevice() async {
    final devices = await TtySerial.listDevices();

    if (!mounted) return;

    if (devices.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0D1A2B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cable_rounded, color: Color(0xFFFF6F00)),
              SizedBox(width: 10),
              Text('TTY Devices',
                  style: TextStyle(color: Colors.white, fontSize: 17)),
            ],
          ),
          content: const Text(
            'No /dev/ttyS* or /dev/ttyUSB* devices found.\n\n'
            'TTY listing only works on the physical Android tablet — '
            'Chrome/desktop returns an empty list.',
            style: TextStyle(color: Colors.redAccent, fontSize: 12),
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
      return;
    }

    final current = AppConfig.ttyPath;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cable_rounded, color: Color(0xFFFF6F00)),
            SizedBox(width: 10),
            Text('Pick TTY Device',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select the /dev/ttyS* port wired to the Reyeah Control Board. '
                'After picking, use "Test Dispense Slot" to confirm the motor fires.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              for (final path in devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    path == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: path == current
                        ? const Color(0xFFFF6F00)
                        : Colors.white38,
                    size: 20,
                  ),
                  title: Text(
                    path,
                    style: TextStyle(
                      color: path == current
                          ? const Color(0xFFFF6F00)
                          : Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: path == current
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, path),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );

    if (picked == null || picked == current) return;

    await AppConfig.setTtyPath(picked);
    if (!mounted) return;
    setState(() {}); // refresh the displayed subtitle

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('TTY port set to $picked'),
        backgroundColor: const Color(0xFFFF6F00),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Pick Lift Platform TTY Device (elevator's second UART) ───────────────

  Future<void> _pickLiftTtyDevice() async {
    final devices = await TtySerial.listDevices();

    if (!mounted) return;

    if (devices.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0D1A2B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.swap_calls_rounded, color: Color(0xFFAB47BC)),
              SizedBox(width: 10),
              Text('TTY Devices',
                  style: TextStyle(color: Colors.white, fontSize: 17)),
            ],
          ),
          content: const Text(
            'No /dev/ttyS* or /dev/ttyUSB* devices found.\n\n'
            'TTY listing only works on the physical Android tablet — '
            'Chrome/desktop returns an empty list.',
            style: TextStyle(color: Colors.redAccent, fontSize: 12),
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
      return;
    }

    final current = AppConfig.ttyPathLift;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.swap_calls_rounded, color: Color(0xFFAB47BC)),
            SizedBox(width: 10),
            Text('Pick Lift TTY Device',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select the /dev/ttyS* port wired to the elevator lift '
                "platform's MCU. On Reyeah T1-02 / T11-PRO / S4 hardware "
                'this is /dev/ttyS8 by default. The main VMC port (above) '
                'should be a different device.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              for (final path in devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    path == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: path == current
                        ? const Color(0xFFAB47BC)
                        : Colors.white38,
                    size: 20,
                  ),
                  title: Text(
                    path,
                    style: TextStyle(
                      color: path == current
                          ? const Color(0xFFAB47BC)
                          : Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: path == current
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, path),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );

    if (picked == null || picked == current) return;

    await AppConfig.setTtyPathLift(picked);
    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lift TTY port set to $picked'),
        backgroundColor: const Color(0xFFAB47BC),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Pick Machine Type (coil vs elevator) ─────────────────────────────────

  /// Human-readable label for the stored machine-type string.
  String _machineTypeLabel(String key) => switch (key) {
        'elevator'        => 'Elevator (side-push, 0xFB)',
        'elevator-spring' => 'Elevator (spring axis, 0xFF)',
        _                 => 'Coil / spring lane',
      };

  Future<void> _pickMachineType() async {
    final current = AppConfig.machineType;
    final options = <(String, String, String)>[
      (
        'coil',
        'Coil / spring lane',
        'Traditional spring-lane vending. Second byte of CMD 0x41 is the '
            'quantity to dispense. Use this for non-lift machines.',
      ),
      (
        'elevator',
        'Elevator — side push (0xFB)',
        'Lift-platform machines (T1-02 / T11-PRO / S4) with a side-push '
            'axis. Default for elevator hardware.',
      ),
      (
        'elevator-spring',
        'Elevator — spring axis (0xFF)',
        'Lift-platform machines whose individual slots still use a '
            'spring (rare hybrid setup).',
      ),
    ];

    final picked = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.precision_manufacturing_rounded, color: Color(0xFF9575CD)),
          SizedBox(width: 10),
          Text('Machine Type',
              style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selects what the second byte of the CMD 0x41 delivery '
                'frame means. Pick the option that matches the physical '
                'vending machine the kiosk is mounted on.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              for (final opt in options) ...[
                InkWell(
                  onTap: () => Navigator.pop(context, opt.$1),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: opt.$1 == current
                            ? const Color(0xFF9575CD)
                            : Colors.white12,
                        width: opt.$1 == current ? 1.5 : 1,
                      ),
                      color: opt.$1 == current
                          ? const Color(0xFF9575CD).withValues(alpha: 0.08)
                          : Colors.transparent,
                    ),
                    child: Row(children: [
                      Icon(
                        opt.$1 == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: opt.$1 == current
                            ? const Color(0xFF9575CD)
                            : Colors.white38,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(opt.$2,
                                style: TextStyle(
                                  color: opt.$1 == current
                                      ? const Color(0xFF9575CD)
                                      : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(height: 3),
                            Text(opt.$3,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );

    if (picked == null || picked == current) return;

    await AppConfig.setMachineType(picked);
    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Machine type set to ${_machineTypeLabel(picked)}'),
        backgroundColor: const Color(0xFF9575CD),
        duration: const Duration(seconds: 3),
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

  // ── Remote APK update ────────────────────────────────────────────────────

  Future<void> _checkForUpdates() async {
    // Show a "checking…" dialog while we poll the backend.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CheckingUpdateDialog(),
    );

    UpdateInfo info;
    String currentVersion;
    try {
      currentVersion = await UpdateService.currentVersionName();
      info = await UpdateService.check();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSimpleDialog(
        title: 'Update check failed',
        message: 'Could not reach the update server.\n\n$e',
        color: Colors.redAccent,
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close checking dialog

    if (!info.available) {
      _showSimpleDialog(
        title: 'You\'re up to date',
        message: 'This kiosk is running version $currentVersion.\nNo newer version is available.',
        color: const Color(0xFF388E3C),
      );
      return;
    }

    // Confirm before downloading.
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.system_update_rounded, color: Color(0xFF388E3C)),
          SizedBox(width: 10),
          Text('Update available', style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Current: $currentVersion\nLatest:  ${info.versionName}',
                style: const TextStyle(color: Colors.white70, fontSize: 13,
                    fontFamily: 'monospace'),
              ),
              if (info.sizeBytes != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Download size: ${(info.sizeBytes! / 1024 / 1024).toStringAsFixed(1)} MB',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              if (info.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Release notes:',
                    style: TextStyle(color: Color(0xFF007ACC), fontSize: 11,
                        fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 6),
                Text(info.releaseNotes,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
              if (info.mandatory) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'This is a MANDATORY update. The kiosk should not skip it.',
                    style: TextStyle(color: Colors.orange, fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later', style: TextStyle(color: Colors.white38)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF388E3C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Download & install'),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;

    // Make sure the user has granted "install unknown apps" permission.
    final canInstall = await UpdateService.canRequestInstalls();
    if (!canInstall) {
      if (!mounted) return;
      await _showSimpleDialog(
        title: 'Permission needed',
        message: 'Android needs your permission to install apps from this source. '
            'Tap OK to open the settings page, then toggle "Allow from this source" '
            'and try the update again.',
        color: const Color(0xFFFF9800),
      );
      await UpdateService.openInstallSettings();
      return;
    }

    // Download + install.
    if (!mounted) return;
    final progressController = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadingDialog(progress: progressController),
    );

    String path;
    try {
      path = await UpdateService.download(
        info,
        onProgress: (received, total) {
          progressController.value = total > 0 ? received / total : 0;
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressController.dispose();
      _showSimpleDialog(
        title: 'Download failed',
        message: e.toString(),
        color: Colors.redAccent,
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    progressController.dispose();

    // CRITICAL: Lock Task Mode (screen pinning) blocks intents to other
    // packages — including Android's PackageInstaller. Without this step
    // the install dialog never appears and the user sees nothing happen
    // after the download completes. Drop out of pinning *before* firing
    // the install intent; onResume() will re-pin automatically when the
    // installer dialog closes or the app relaunches with the new APK.
    await KioskLockdown.exitKioskMode();

    final launched = await UpdateService.installApk(path);
    if (!mounted) return;
    if (!launched) {
      _showSimpleDialog(
        title: 'Install failed',
        message: 'Could not launch the system installer. The APK is saved at:\n$path',
        color: Colors.redAccent,
      );
    }
    // If launched succeeded, Android takes over from here. After the admin
    // taps "Install" on the system dialog, the kiosk relaunches with the
    // new version.
  }

  Future<void> _showSimpleDialog({
    required String title,
    required String message,
    required Color color,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(color: color, fontSize: 17)),
        content: Text(message,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(color: Color(0xFF007ACC),
                    fontWeight: FontWeight.bold)),
          ),
        ],
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
                readOnly: true,
                showCursor: true,
                enableInteractiveSelection: false,
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
                onTap: () => showKeypad(
                  context,
                  controller: _ctrl,
                  mode: KeypadMode.alphanumeric,
                  obscureText: _obscure,
                  title: 'LOTTERY DRAW TOKEN',
                  hint: 'Per-lottery token from vms-cloud',
                  onCommitted: (_) => setState(() => _saved = null),
                ),
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
                readOnly: true,
                showCursor: true,
                enableInteractiveSelection: false,
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
                onTap: () => showKeypad(
                  context,
                  controller: _ctrl,
                  mode: KeypadMode.alphanumeric,
                  obscureText: _obscure,
                  title: 'MANAGEMENT TOKEN',
                  hint: 'Bearer token from vms-cloud settings',
                  onCommitted: (_) => setState(() => _saved = null),
                ),
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
          readOnly: true,
          showCursor: true,
          enableInteractiveSelection: false,
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
          onTap: () => showKeypad(
            context,
            controller: ctrl,
            mode: KeypadMode.alphanumeric,
            obscureText: obscure,
            title: label.toUpperCase(),
            hint: hint,
          ),
        ),
      ],
    );
  }
}

// ── PIN Dialog ────────────────────────────────────────────────────────────────

/// Returns true when the operator enters the correct admin PIN.
/// Does not navigate to [AdminConfigScreen].
Future<bool> verifyAdminPin(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _PinVerifyDialog(),
  );
  return result == true;
}

/// PIN dialog that owns its [TextEditingController] lifecycle.
class _PinVerifyDialog extends StatefulWidget {
  const _PinVerifyDialog();

  @override
  State<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<_PinVerifyDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == AppConfig.adminPin) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Incorrect PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D1A2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: Color(0xFF007ACC), size: 22),
          SizedBox(width: 10),
          Text('Admin PIN',
              style: TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter admin PIN to continue.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
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
              errorText: _error,
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
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007ACC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

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
              readOnly: true,
              showCursor: true,
              enableInteractiveSelection: false,
              obscureText: true,
              keyboardType: TextInputType.number,
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
              onTap: () async {
                await showKeypad(
                  ctx,
                  controller: controller,
                  mode: KeypadMode.numeric,
                  maxLength: 8,
                  obscureText: true,
                  title: 'ADMIN PIN',
                  hint: '••••',
                  submitLabel: 'ENTER',
                );
                if (!ctx.mounted) return;
                _checkPin(ctx, controller.text,
                    (e) => setDialogState(() => error = e));
              },
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

// ── Update dialogs ───────────────────────────────────────────────────────────

/// Indeterminate spinner shown while we poll the backend for the latest version.
class _CheckingUpdateDialog extends StatelessWidget {
  const _CheckingUpdateDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D1A2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(
              color: Color(0xFF388E3C), strokeWidth: 2.5,
            ),
          ),
          SizedBox(width: 16),
          Text('Checking for updates…',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
}

/// Determinate progress bar shown while the APK downloads.
class _DownloadingDialog extends StatelessWidget {
  final ValueNotifier<double> progress;
  const _DownloadingDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D1A2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.download_rounded, color: Color(0xFF388E3C)),
        SizedBox(width: 10),
        Text('Downloading update',
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ]),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value > 0 ? value : null,
                  minHeight: 10,
                  backgroundColor: const Color(0xFF060E18),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF388E3C)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value > 0
                    ? '${(value * 100).toStringAsFixed(0)}% complete'
                    : 'Starting download…',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'After download, Android will ask you to confirm the install.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Dispense progress dialog
// ─────────────────────────────────────────────────────────────────────────────

enum _DispenseStage { sending, motorTurning, coolingDown, success, error }

/// Self-contained progress dialog for the admin "Test Dispense Slot" flow.
///
/// Owns its own future so the dispense pipeline can't tear down the
/// surrounding admin route mid-flight. On success the dialog auto-dismisses
/// after a beat so the operator lands back on the same admin screen they
/// launched from. On error it stays open with the error text and a Close
/// button so the admin can read it before navigating away.
class _DispenseProgressDialog extends StatefulWidget {
  final int slotNumber;
  const _DispenseProgressDialog({required this.slotNumber});

  @override
  State<_DispenseProgressDialog> createState() =>
      _DispenseProgressDialogState();
}

class _DispenseProgressDialogState extends State<_DispenseProgressDialog> {
  _DispenseStage _stage = _DispenseStage.sending;
  String _errorMsg = '';
  Timer? _motorTurningTimer;
  Timer? _coolingDownTimer;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    // Roll the visible stage forward on a timer so the operator sees
    // motion even though the underlying TTY dispense is a single 5–7 s
    // call. These transitions are cosmetic — the real source of truth
    // is the DispenseResult that comes back from the service.
    //
    // Each timer only advances from the *previous* cosmetic stage. Without
    // that guard, a fast-failing dispense (TTY open error in < 1 s) would
    // set _stage = error, then 1 s later the timer would overwrite it back
    // to motorTurning, then 5 s later to coolingDown — and the operator
    // sees the red error flash and disappear, stuck forever on "Almost done".
    _motorTurningTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_stage == _DispenseStage.sending) {
        setState(() => _stage = _DispenseStage.motorTurning);
      }
    });
    _coolingDownTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_stage == _DispenseStage.motorTurning) {
        setState(() => _stage = _DispenseStage.coolingDown);
      }
    });

    _runDispense();
  }

  void _cancelCosmeticTimers() {
    _motorTurningTimer?.cancel();
    _coolingDownTimer?.cancel();
  }

  Future<void> _runDispense() async {
    try {
      final result =
          await VendingMachineService.testDispenseSlot(widget.slotNumber);
      if (!mounted) return;

      // Belt-and-braces: cancel cosmetic timers before transitioning to a
      // terminal stage so a timer that's already queued on the microtask
      // loop can't slip through and overwrite success/error.
      _cancelCosmeticTimers();

      if (result.status == DispenseStatus.success) {
        setState(() => _stage = _DispenseStage.success);
        // Auto-close on success so the operator lands back on the admin
        // panel without having to tap Close. 1.5 s is enough to register
        // the green check visually.
        _autoCloseTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) Navigator.of(context).pop();
        });
      } else {
        setState(() {
          _stage = _DispenseStage.error;
          _errorMsg = result.errorMessage ?? 'Unknown error';
        });
      }
    } catch (e) {
      if (!mounted) return;
      _cancelCosmeticTimers();
      setState(() {
        _stage = _DispenseStage.error;
        _errorMsg = 'Unexpected: $e';
      });
    }
  }

  @override
  void dispose() {
    _motorTurningTimer?.cancel();
    _coolingDownTimer?.cancel();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDone = _stage == _DispenseStage.success ||
        _stage == _DispenseStage.error;

    return AlertDialog(
      backgroundColor: const Color(0xFF0D1A2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(_titleIcon(), color: _titleColor()),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_titleText(widget.slotNumber),
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 24, height: 24,
                  child: _stageIndicator(),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(
                  _stageDescription(),
                  style: TextStyle(
                    color: isDone
                        ? (_stage == _DispenseStage.success
                            ? Colors.greenAccent
                            : Colors.redAccent)
                        : Colors.white70,
                    fontSize: 13,
                  ),
                )),
              ],
            ),
            if (_stage == _DispenseStage.error) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Text(_errorMsg,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
      actions: isDone
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close',
                    style: TextStyle(color: Color(0xFF007ACC))),
              ),
            ]
          : null,
    );
  }

  // ── Stage helpers ────────────────────────────────────────────────────────

  Widget _stageIndicator() {
    switch (_stage) {
      case _DispenseStage.success:
        return const Icon(Icons.check_circle_rounded,
            color: Colors.greenAccent, size: 24);
      case _DispenseStage.error:
        return const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 24);
      default:
        return const CircularProgressIndicator(
            color: Color(0xFF4CAF50), strokeWidth: 2.5);
    }
  }

  String _stageDescription() {
    switch (_stage) {
      case _DispenseStage.sending:
        return 'Sending UART delivery command…';
      case _DispenseStage.motorTurning:
        return 'Motor turning — watch the machine for product drop.';
      case _DispenseStage.coolingDown:
        return 'Almost done — board is reporting status.';
      case _DispenseStage.success:
        return 'Success — slot ${widget.slotNumber} dispensed.';
      case _DispenseStage.error:
        return 'Dispense failed.';
    }
  }

  IconData _titleIcon() {
    switch (_stage) {
      case _DispenseStage.success:
        return Icons.check_circle_rounded;
      case _DispenseStage.error:
        return Icons.error_outline_rounded;
      default:
        return Icons.local_shipping_rounded;
    }
  }

  Color _titleColor() {
    switch (_stage) {
      case _DispenseStage.success:
        return Colors.greenAccent;
      case _DispenseStage.error:
        return Colors.redAccent;
      default:
        return const Color(0xFF4CAF50);
    }
  }

  String _titleText(int slot) {
    switch (_stage) {
      case _DispenseStage.success:
        return 'Dispense complete';
      case _DispenseStage.error:
        return 'Dispense error';
      default:
        return 'Dispensing slot $slot…';
    }
  }
}
