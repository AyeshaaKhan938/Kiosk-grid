import 'package:flutter/material.dart';
import '../services/app_config.dart';
import 'product_browser_screen.dart';

/// Pantalla de configuración inicial — se muestra solo la primera vez
/// que la app arranca sin estar configurada.
///
/// El técnico/operador la llena al instalar la app en la máquina.
/// Después de guardar, nunca vuelve a aparecer (a menos que se resetee).
class SetupScreen extends StatefulWidget {
  /// Si [isEditing] es true, viene desde AdminConfigScreen (ya configurado).
  final bool isEditing;

  const SetupScreen({super.key, this.isEditing = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _apiUrlCtrl = TextEditingController();
  final _machineCtrl = TextEditingController();
  final _tokenCtrl  = TextEditingController();
  final _pinCtrl    = TextEditingController();

  bool _saving = false;
  bool _showPin = false;

  @override
  void initState() {
    super.initState();
    // Pre-cargar valores actuales si estamos editando
    if (widget.isEditing) {
      _apiUrlCtrl.text  = AppConfig.apiBaseUrl;
      _machineCtrl.text = AppConfig.machineNo;
      _tokenCtrl.text   = AppConfig.lotteryToken;
      _pinCtrl.text     = AppConfig.adminPin;
    }
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _machineCtrl.dispose();
    _tokenCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    await AppConfig.save(
      apiBaseUrl:   _apiUrlCtrl.text,
      machineNo:    _machineCtrl.text,
      lotteryToken: _tokenCtrl.text,
      adminPin:     _pinCtrl.text,
      language:     AppConfig.language,
    );

    if (!mounted) return;

    if (widget.isEditing) {
      Navigator.pop(context); // Volver al admin panel
    } else {
      // Primera configuración → ir a la app
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProductBrowserScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fondo
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: 1.5,
                colors: [Color(0xFF0A1628), Colors.black],
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007ACC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'VMFS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isEditing
                                    ? 'Edit Configuration'
                                    : 'Machine Setup',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.isEditing
                                    ? 'Update this machine\'s settings'
                                    : 'Configure this kiosk before first use',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),

                      // ── Campos ──────────────────────────────────────────
                      _SectionLabel('Backend'),
                      const SizedBox(height: 12),

                      _Field(
                        controller: _apiUrlCtrl,
                        label: 'API Base URL',
                        hint: 'https://your-domain.com/api/v1',
                        icon: Icons.cloud_outlined,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          if (!v.startsWith('http')) {
                            return 'Must start with http:// or https://';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 32),
                      _SectionLabel('Machine'),
                      const SizedBox(height: 12),

                      _Field(
                        controller: _machineCtrl,
                        label: 'Machine Number',
                        hint: 'e.g. VMFS-001 or 866902296600001',
                        icon: Icons.point_of_sale_outlined,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),

                      const SizedBox(height: 16),

                      _Field(
                        controller: _tokenCtrl,
                        label: 'Lottery Token',
                        hint: 'From vms-cloud admin panel',
                        icon: Icons.key_outlined,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),

                      const SizedBox(height: 32),
                      _SectionLabel('Security'),
                      const SizedBox(height: 12),

                      _Field(
                        controller: _pinCtrl,
                        label: 'Admin PIN',
                        hint: '4-digit PIN to access settings',
                        icon: Icons.lock_outline,
                        obscure: !_showPin,
                        suffix: IconButton(
                          icon: Icon(
                            _showPin
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.white38,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPin = !_showPin),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (v.trim().length < 4) return 'Minimum 4 digits';
                          return null;
                        },
                      ),

                      const SizedBox(height: 40),

                      // Botón guardar
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007ACC),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  widget.isEditing ? 'Save Changes' : 'Save & Start',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),

                      if (widget.isEditing) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white38),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF007ACC),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF0D1A2B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF007ACC), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }
}
