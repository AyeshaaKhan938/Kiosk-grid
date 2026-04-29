import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import '../services/app_config.dart';
import '../services/reyeah_service.dart';
import '../services/vending_machine_service.dart';
import 'setup_wizard_screen.dart';

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
              subtitle: 'Change API URL, Machine No., Lottery Token or PIN',
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
              'Lottery Token',
              AppConfig.lotteryToken.isNotEmpty
                  ? '${AppConfig.lotteryToken.substring(0, 8)}…'
                  : '—',
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
