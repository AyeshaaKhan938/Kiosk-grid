import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_config.dart';
import '../services/reyeah_service.dart';
import '../widgets/onscreen_keypad.dart';
import 'idle_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VMFS Setup Wizard — aparece una sola vez al instalar la app.
//
// Steps:
//   1. Network       → verificar WiFi / Ethernet
//   2. Backend       → API URL + Lottery Token + Test Connection
//   3. This Machine  → Machine No + Admin PIN + Confirm PIN
// ─────────────────────────────────────────────────────────────────────────────

class SetupWizardScreen extends StatefulWidget {
  /// Si [isEditing] viene desde AdminConfigScreen.
  final bool isEditing;
  const SetupWizardScreen({super.key, this.isEditing = false});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 3;

  // ── Datos del wizard ──────────────────────────────────────────────────────
  // Defaults are pulled from AppConfig in initState — on a fresh install
  // that returns the production constants baked into app_config.dart, so
  // the URL / token fields are pre-populated with the real prod values
  // instead of a stale test URL. On re-config from the admin panel the
  // previously-saved values flow through the same path.
  late String _backendMode;
  late String _apiBaseUrl;
  late String _managementToken;
  late String _machineNo;
  late String _vmBaseUrl;
  late String _vmAppId;
  late String _vmAppSecret;
  late String _vmMachineNo;
  late String _adminPin;

  @override
  void initState() {
    super.initState();
    _backendMode     = AppConfig.backendMode;
    _apiBaseUrl      = AppConfig.apiBaseUrl;
    _managementToken = AppConfig.managementToken;
    _machineNo       = AppConfig.machineNo;
    _vmBaseUrl       = AppConfig.vmBaseUrl;
    _vmAppId         = AppConfig.vmAppId;
    _vmAppSecret     = AppConfig.vmAppSecret;
    _vmMachineNo     = AppConfig.vmMachineNo;
    _adminPin        = AppConfig.adminPin;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Navegación ────────────────────────────────────────────────────────────

  void _next() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _back() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    // Guardar modo de backend
    await AppConfig.setBackendMode(_backendMode);

    if (_backendMode == 'reyeah') {
      // Guardar credenciales Reyeah
      await AppConfig.saveReyeah(
        baseUrl:   _vmBaseUrl.isNotEmpty ? _vmBaseUrl : AppConfig.vmBaseUrl,
        appId:     _vmAppId,
        appSecret: _vmAppSecret,
        machineNo: _vmMachineNo,
      );
      // Guardar config base (marca como configurado; PIN; otros campos vacíos/previos)
      await AppConfig.save(
        apiBaseUrl:      AppConfig.apiBaseUrl,
        machineNo:       _vmMachineNo,
        managementToken: AppConfig.managementToken,
        adminPin:        _adminPin,
        language:        'en',
      );
    } else {
      await AppConfig.save(
        apiBaseUrl:      _apiBaseUrl,
        machineNo:       _machineNo,
        managementToken: _managementToken,
        adminPin:        _adminPin,
        language:        'en',
      );
    }

    if (!mounted) return;

    if (widget.isEditing) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const IdleScreen()),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
                radius: 1.6,
                colors: [Color(0xFF0A1628), Colors.black],
              ),
            ),
          ),

          Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentStep = i),
                  children: [
                    _StepNetwork(
                      onNext: _next,
                    ),
                    _StepBackend(
                      initialMode:             _backendMode,
                      initialUrl:              _apiBaseUrl,
                      initialManagementToken:  _managementToken,
                      initialVmBaseUrl:        _vmBaseUrl,
                      initialVmAppId:          _vmAppId,
                      initialVmAppSecret:      _vmAppSecret,
                      initialVmMachineNo:      _vmMachineNo,
                      onNext: (config) {
                        setState(() {
                          _backendMode      = config.backendMode;
                          _apiBaseUrl       = config.apiBaseUrl;
                          _managementToken  = config.managementToken;
                          _vmBaseUrl        = config.vmBaseUrl;
                          _vmAppId          = config.vmAppId;
                          _vmAppSecret      = config.vmAppSecret;
                          _vmMachineNo      = config.vmMachineNo;
                        });
                        _next();
                      },
                      onBack: _back,
                    ),
                    _StepMachine(
                      initialMachineNo: _machineNo,
                      initialPin:       _adminPin,
                      isEditing:        widget.isEditing,
                      backendMode:      _backendMode,
                      onFinish: (machineNo, pin) {
                        setState(() {
                          _machineNo = machineNo;
                          _adminPin  = pin;
                        });
                        _finish();
                      },
                      onBack: _back,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Top bar con progress ──────────────────────────────────────────────────

  Widget _buildTopBar() {
    final labels = ['Network', 'Backend', 'Machine'];

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF007ACC).withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF007ACC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('VMFS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 2,
                )),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Row(
              children: List.generate(_totalSteps, (i) {
                final active   = i == _currentStep;
                final done     = i < _currentStep;
                final color    = done || active
                    ? const Color(0xFF007ACC)
                    : Colors.white12;

                return Expanded(
                  child: Row(
                    children: [
                      // Círculo
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done
                              ? const Color(0xFF007ACC)
                              : active
                                  ? Colors.transparent
                                  : Colors.transparent,
                          border: Border.all(color: color, width: 2),
                        ),
                        child: Center(
                          child: done
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 16)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: active
                                        ? const Color(0xFF007ACC)
                                        : Colors.white24,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Label
                      Text(
                        labels[i],
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : done
                                  ? const Color(0xFF007ACC)
                                  : Colors.white24,
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      // Línea separadora
                      if (i < _totalSteps - 1) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: i < _currentStep
                                ? const Color(0xFF007ACC).withValues(alpha: 0.5)
                                : Colors.white12,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — Network
// ─────────────────────────────────────────────────────────────────────────────

class _StepNetwork extends StatefulWidget {
  final VoidCallback onNext;
  const _StepNetwork({required this.onNext});

  @override
  State<_StepNetwork> createState() => _StepNetworkState();
}

class _StepNetworkState extends State<_StepNetwork> {
  List<ConnectivityResult>? _status;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final result = await Connectivity().checkConnectivity();
    if (mounted) setState(() { _status = result; _checking = false; });
  }

  bool get _isConnected =>
      _status != null &&
      _status!.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.mobile);

  String get _statusLabel {
    if (_checking || _status == null) return 'Checking…';
    if (_status!.contains(ConnectivityResult.wifi))     return 'Connected via Wi-Fi';
    if (_status!.contains(ConnectivityResult.ethernet)) return 'Connected via Ethernet';
    if (_status!.contains(ConnectivityResult.mobile))   return 'Connected via Mobile Data';
    return 'No internet connection';
  }

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Network Connection',
      subtitle: 'Make sure this device has internet access before continuing',
      icon: Icons.wifi_rounded,
      onNext: widget.onNext,
      // No back button — es el primer step
      nextEnabled: _isConnected,
      nextLabel: _isConnected ? 'Continue' : 'Connect first',
      child: Column(
        children: [
          // Status card
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFF0D1A2B),
              border: Border.all(
                color: _checking
                    ? Colors.white12
                    : _isConnected
                        ? Colors.green.withValues(alpha: 0.5)
                        : Colors.redAccent.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                _checking
                    ? const CircularProgressIndicator(
                        color: Color(0xFF007ACC), strokeWidth: 3)
                    : Icon(
                        _isConnected
                            ? Icons.check_circle_rounded
                            : Icons.signal_wifi_off_rounded,
                        color: _isConnected ? Colors.green : Colors.redAccent,
                        size: 56,
                      ),
                const SizedBox(height: 16),
                Text(
                  _statusLabel,
                  style: TextStyle(
                    color: _checking
                        ? Colors.white54
                        : _isConnected
                            ? Colors.green
                            : Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Botones
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _OutlineBtn(
                icon: Icons.refresh_rounded,
                label: 'Check again',
                onTap: _check,
              ),
              const SizedBox(width: 16),
              _OutlineBtn(
                icon: Icons.settings_rounded,
                label: 'Open Wi-Fi Settings',
                onTap: () async {
                  // Abre los ajustes de WiFi del sistema Android
                  const platform = MethodChannel('vmfs/system');
                  try {
                    await platform.invokeMethod('openWifiSettings');
                  } catch (_) {
                    // Canal no implementado en web/desktop — ignorar
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Text(
            'Connect this device to your store\'s Wi-Fi or Ethernet\nbefore proceeding. Mobile data also works.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — Backend  (mode-aware: Reyeah Cloud | vms-cloud)
// ─────────────────────────────────────────────────────────────────────────────

/// Datos que recoge el step de backend al confirmar.
class _BackendConfig {
  final String backendMode;
  final String apiBaseUrl;
  final String managementToken;
  final String vmBaseUrl;
  final String vmAppId;
  final String vmAppSecret;
  final String vmMachineNo;

  const _BackendConfig({
    required this.backendMode,
    required this.apiBaseUrl,
    required this.managementToken,
    required this.vmBaseUrl,
    required this.vmAppId,
    required this.vmAppSecret,
    required this.vmMachineNo,
  });
}

class _StepBackend extends StatefulWidget {
  final String initialMode;
  final String initialUrl;
  final String initialManagementToken;
  final String initialVmBaseUrl;
  final String initialVmAppId;
  final String initialVmAppSecret;
  final String initialVmMachineNo;
  final void Function(_BackendConfig config) onNext;
  final VoidCallback onBack;

  const _StepBackend({
    required this.initialMode,
    required this.initialUrl,
    required this.initialManagementToken,
    required this.initialVmBaseUrl,
    required this.initialVmAppId,
    required this.initialVmAppSecret,
    required this.initialVmMachineNo,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<_StepBackend> createState() => _StepBackendState();
}

class _StepBackendState extends State<_StepBackend> {
  // ── Modo ──────────────────────────────────────────────────────────────────
  late String _mode; // 'reyeah' | 'vmscloud'

  // ── vms-cloud ─────────────────────────────────────────────────────────────
  late final TextEditingController _urlCtrl;
  late final TextEditingController _mgmtTokenCtrl;
  bool    _testingUrl   = false;
  bool    _testingToken = false;
  String? _urlStatus;
  String? _tokenStatus;

  // ── Reyeah Cloud ─────────────────────────────────────────────────────────
  late final TextEditingController _vmBaseUrlCtrl;
  late final TextEditingController _vmAppIdCtrl;
  late final TextEditingController _vmAppSecretCtrl;
  late final TextEditingController _vmMachineNoCtrl;
  bool    _obscureSecret  = true;
  bool    _testingReyeah  = false;
  String? _reyeahStatus;  // null=idle, '' = ok, 'msg' = error

  @override
  void initState() {
    super.initState();
    _mode           = widget.initialMode.isEmpty ? 'reyeah' : widget.initialMode;
    _urlCtrl        = TextEditingController(text: widget.initialUrl);
    _mgmtTokenCtrl  = TextEditingController(text: widget.initialManagementToken);
    _vmBaseUrlCtrl  = TextEditingController(
        text: widget.initialVmBaseUrl.isNotEmpty
            ? widget.initialVmBaseUrl
            : 'https://4020y425z1.uicp.fun');
    _vmAppIdCtrl    = TextEditingController(text: widget.initialVmAppId);
    _vmAppSecretCtrl = TextEditingController(text: widget.initialVmAppSecret);
    _vmMachineNoCtrl = TextEditingController(text: widget.initialVmMachineNo);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _mgmtTokenCtrl.dispose();
    _vmBaseUrlCtrl.dispose();
    _vmAppIdCtrl.dispose();
    _vmAppSecretCtrl.dispose();
    _vmMachineNoCtrl.dispose();
    super.dispose();
  }

  // ── vms-cloud helpers ─────────────────────────────────────────────────────

  Future<void> _testUrl() async {
    if (_urlCtrl.text.trim().isEmpty) return;
    setState(() { _testingUrl = true; _urlStatus = null; });
    final err = await AppConfig.testConnection(_urlCtrl.text);
    if (mounted) setState(() { _testingUrl = false; _urlStatus = err ?? ''; });
  }

  Future<void> _testToken() async {
    if (_mgmtTokenCtrl.text.trim().isEmpty) return;
    setState(() { _testingToken = true; _tokenStatus = null; });
    final err = await AppConfig.testLotteryToken(_urlCtrl.text, _mgmtTokenCtrl.text);
    if (mounted) setState(() { _testingToken = false; _tokenStatus = err ?? ''; });
  }

  // ── Reyeah helpers ────────────────────────────────────────────────────────

  Future<void> _testReyeah() async {
    final appId     = _vmAppIdCtrl.text.trim();
    final appSecret = _vmAppSecretCtrl.text.trim();
    final machineNo = _vmMachineNoCtrl.text.trim();
    if (appId.isEmpty || appSecret.isEmpty || machineNo.isEmpty) return;

    setState(() { _testingReyeah = true; _reyeahStatus = null; });

    // Guardar temporalmente para que ReyeahService las use
    await AppConfig.saveReyeah(
      baseUrl:   _vmBaseUrlCtrl.text.trim(),
      appId:     appId,
      appSecret: appSecret,
      machineNo: machineNo,
    );
    await AppConfig.setBackendMode('reyeah');

    final err = await ReyeahService.testCredentials();
    if (mounted) setState(() { _testingReyeah = false; _reyeahStatus = err ?? ''; });
  }

  // ── canContinue ───────────────────────────────────────────────────────────

  bool get _canContinue {
    if (_mode == 'reyeah') {
      // Con credenciales verificadas es ideal, pero permitir continuar
      // si al menos App ID + Secret + Machine No. están escritos.
      return _vmAppIdCtrl.text.trim().isNotEmpty &&
             _vmAppSecretCtrl.text.trim().isNotEmpty &&
             _vmMachineNoCtrl.text.trim().isNotEmpty;
    }
    // Solo se requiere URL verificada. El token es opcional — se puede
    // configurar en cualquier momento desde el Admin Panel.
    return _urlStatus == '';
  }

  _BackendConfig get _config => _BackendConfig(
    backendMode:     _mode,
    apiBaseUrl:      _urlCtrl.text.trim(),
    managementToken: _mgmtTokenCtrl.text.trim(),
    vmBaseUrl:       _vmBaseUrlCtrl.text.trim(),
    vmAppId:         _vmAppIdCtrl.text.trim(),
    vmAppSecret:     _vmAppSecretCtrl.text.trim(),
    vmMachineNo:     _vmMachineNoCtrl.text.trim(),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Backend Connection',
      subtitle: 'Choose how this kiosk connects to the cloud',
      icon: Icons.cloud_outlined,
      onNext: () => widget.onNext(_config),
      onBack: widget.onBack,
      nextEnabled: _canContinue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Mode selector ──────────────────────────────────────────────
          _buildModeSelector(),
          const SizedBox(height: 28),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),

          // ── Fields depending on mode ───────────────────────────────────
          if (_mode == 'reyeah') _buildReyeahFields()
          else                    _buildVmsCloudFields(),
        ],
      ),
    );
  }

  // ── Mode selector widget ──────────────────────────────────────────────────

  Widget _buildModeSelector() {
    return Row(
      children: [
        Expanded(child: _ModeChip(
          label: 'Reyeah Cloud',
          sublabel: 'Direct machine API',
          icon: Icons.cloud_outlined,
          color: const Color(0xFF00BCD4),
          selected: _mode == 'reyeah',
          onTap: () => setState(() {
            _mode = 'reyeah';
            _reyeahStatus = null;
          }),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ModeChip(
          label: 'vms-cloud',
          sublabel: 'VMFS own backend',
          icon: Icons.dns_outlined,
          color: const Color(0xFF007ACC),
          selected: _mode == 'vmscloud',
          onTap: () => setState(() {
            _mode = 'vmscloud';
            _urlStatus = null;
            _tokenStatus = null;
          }),
        )),
      ],
    );
  }

  // ── Reyeah Cloud fields ───────────────────────────────────────────────────

  Widget _buildReyeahFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizardField(
          controller: _vmBaseUrlCtrl,
          label: 'Base URL',
          hint: 'https://4020y425z1.uicp.fun',
          icon: Icons.link_rounded,
          onChanged: (_) => setState(() => _reyeahStatus = null),
        ),
        const SizedBox(height: 20),
        _WizardField(
          controller: _vmAppIdCtrl,
          label: 'App ID',
          hint: 'Your Reyeah App ID',
          icon: Icons.badge_outlined,
          onChanged: (_) => setState(() => _reyeahStatus = null),
        ),
        const SizedBox(height: 20),
        _WizardField(
          controller: _vmAppSecretCtrl,
          label: 'App Secret',
          hint: '••••••••',
          icon: Icons.key_outlined,
          obscure: _obscureSecret,
          onChanged: (_) => setState(() => _reyeahStatus = null),
          suffix: IconButton(
            icon: Icon(
              _obscureSecret ? Icons.visibility_off : Icons.visibility,
              color: Colors.white38, size: 18),
            onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
          ),
        ),
        const SizedBox(height: 20),
        _WizardField(
          controller: _vmMachineNoCtrl,
          label: 'Machine No.',
          hint: 'e.g. 866903255700003',
          icon: Icons.point_of_sale_outlined,
          onChanged: (_) => setState(() => _reyeahStatus = null),
          suffix: _TestButton(
            testing: _testingReyeah,
            status: _reyeahStatus,
            label: 'Test',
            onTap: _canTestReyeah ? _testReyeah : null,
          ),
        ),
        if (_reyeahStatus != null) ...[
          const SizedBox(height: 8),
          if (_reyeahStatus == '')
            _StatusChip(ok: true, message: 'Connected to Reyeah Cloud ✓')
          else
            _RawResponseBox(text: _reyeahStatus!),
        ],
        const SizedBox(height: 16),
        const Text(
          'Get your App ID, App Secret and Machine No. from\nyour Reyeah Cloud dashboard.',
          style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }

  bool get _canTestReyeah =>
      _vmAppIdCtrl.text.trim().isNotEmpty &&
      _vmAppSecretCtrl.text.trim().isNotEmpty &&
      _vmMachineNoCtrl.text.trim().isNotEmpty;

  // ── vms-cloud fields ──────────────────────────────────────────────────────

  Widget _buildVmsCloudFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WizardField(
          controller: _urlCtrl,
          label: 'API Base URL',
          hint: 'https://your-domain.com/api/v1',
          icon: Icons.link_rounded,
          onChanged: (_) => setState(() { _urlStatus = null; _tokenStatus = null; }),
          suffix: _TestButton(
            testing: _testingUrl,
            status: _urlStatus,
            label: 'Test',
            onTap: _testUrl,
          ),
        ),
        if (_urlStatus != null) ...[
          const SizedBox(height: 6),
          _StatusChip(ok: _urlStatus == '', message: _urlStatus == ''
              ? 'Server reachable ✓'
              : _urlStatus!),
        ],
        const SizedBox(height: 24),
        // ── Management API Token (OPTIONAL) ───────────────────────────
        Row(children: [
          const Text('MANAGEMENT API TOKEN',
              style: TextStyle(color: Colors.white38, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: const Text('Optional',
                style: TextStyle(color: Colors.orange,
                    fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        _WizardField(
          controller: _mgmtTokenCtrl,
          label: '',
          hint: 'Bearer token for Admin Panel — skip to configure later',
          icon: Icons.admin_panel_settings_outlined,
          enabled: _urlStatus == '',
          onChanged: (_) => setState(() => _tokenStatus = null),
          suffix: _mgmtTokenCtrl.text.trim().isNotEmpty
              ? _TestButton(
                  testing: _testingToken,
                  status: _tokenStatus,
                  label: 'Verify',
                  onTap: _urlStatus == '' ? _testToken : null,
                )
              : null,
        ),
        if (_tokenStatus != null) ...[
          const SizedBox(height: 6),
          _StatusChip(ok: _tokenStatus == '', message: _tokenStatus == ''
              ? 'Token valid ✓'
              : _tokenStatus!),
        ],
        const SizedBox(height: 10),
        const Text(
          'Leave blank to skip — set it later from Admin Settings\nto unlock the Admin Panel (dashboard, inventory, orders).',
          style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3 — Machine
// ─────────────────────────────────────────────────────────────────────────────

class _StepMachine extends StatefulWidget {
  final String initialMachineNo;
  final String initialPin;
  final bool isEditing;
  /// Cuando es 'reyeah', el campo Machine No. se oculta (ya se capturó en el step anterior).
  final String backendMode;
  final void Function(String machineNo, String pin) onFinish;
  final VoidCallback onBack;

  const _StepMachine({
    required this.initialMachineNo,
    required this.initialPin,
    required this.isEditing,
    this.backendMode = 'vmscloud',
    required this.onFinish,
    required this.onBack,
  });

  @override
  State<_StepMachine> createState() => _StepMachineState();
}

class _StepMachineState extends State<_StepMachine> {
  late final TextEditingController _machineCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pinConfirmCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _showPin = false;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _machineCtrl    = TextEditingController(text: widget.initialMachineNo);
    _pinCtrl        = TextEditingController(text: widget.isEditing ? widget.initialPin : '');
    _pinConfirmCtrl = TextEditingController(text: widget.isEditing ? widget.initialPin : '');
  }

  @override
  void dispose() {
    _machineCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    widget.onFinish(_machineCtrl.text.trim(), _pinCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'This Machine',
      subtitle: 'Identify this kiosk and set your admin PIN',
      icon: Icons.point_of_sale_outlined,
      showNext: false,
      onBack: widget.onBack,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Machine number — solo para vms-cloud
            if (widget.backendMode != 'reyeah') ...[
              _WizardField(
                controller: _machineCtrl,
                label: 'Machine Number',
                hint: 'e.g. VMFS-001  (must match vms-cloud)',
                icon: Icons.point_of_sale_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 24),
            ],

            // Admin PIN
            _WizardField(
              controller: _pinCtrl,
              label: 'Admin PIN',
              hint: 'At least 4 digits',
              icon: Icons.lock_outline,
              obscure: !_showPin,
              keyboardType: TextInputType.number,
              suffix: IconButton(
                icon: Icon(
                  _showPin ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                  size: 18,
                ),
                onPressed: () => setState(() => _showPin = !_showPin),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (v.trim().length < 4) return 'Minimum 4 characters';
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Confirm PIN
            _WizardField(
              controller: _pinConfirmCtrl,
              label: 'Confirm PIN',
              hint: 'Repeat your admin PIN',
              icon: Icons.lock_outline,
              obscure: !_showPin,
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v != _pinCtrl.text) return 'PINs do not match';
                return null;
              },
            ),

            const SizedBox(height: 32),

            // Finish button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
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
                        widget.isEditing ? 'Save Changes' : '🚀  Launch Kiosk',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ModeChip — selector de modo de backend en el wizard
// ─────────────────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : const Color(0xFF0D1A2B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? color : Colors.white38, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        color: selected ? color : Colors.white54,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      )),
                  Text(sublabel,
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shell compartido — frame visual de cada step
// ─────────────────────────────────────────────────────────────────────────────

class _StepShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final bool nextEnabled;
  final String nextLabel;
  final bool showNext;

  const _StepShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.onNext,
    this.onBack,
    this.nextEnabled = true,
    this.nextLabel = 'Continue',
    this.showNext = true,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step header
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007ACC).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF007ACC).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(icon, color: const Color(0xFF007ACC), size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(height: 3),
                        Text(subtitle,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            )),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
              const Divider(color: Colors.white10),
              const SizedBox(height: 28),

              // Contenido del step
              child,

              // Navegación
              if (showNext) ...[
                const SizedBox(height: 32),
                Row(
                  children: [
                    if (onBack != null)
                      TextButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white38, size: 18),
                        label: const Text('Back',
                            style: TextStyle(color: Colors.white38)),
                      ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: (nextEnabled && onNext != null) ? onNext : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007ACC),
                        disabledBackgroundColor:
                            const Color(0xFF007ACC).withValues(alpha: 0.25),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(nextLabel,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              )),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else if (onBack != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white38, size: 18),
                  label: const Text('Back',
                      style: TextStyle(color: Colors.white38)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares reutilizables
// ─────────────────────────────────────────────────────────────────────────────

class _WizardField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final bool enabled;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;

  const _WizardField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.enabled = true,
    this.suffix,
    this.keyboardType,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    // Pick the keypad layout from the requested keyboard type. Reyeah
    // tablets have no system IME — every field opens our keypad sheet on
    // tap regardless of `keyboardType`, which is otherwise ignored.
    final KeypadMode mode = (keyboardType == TextInputType.number ||
            keyboardType == TextInputType.phone)
        ? KeypadMode.numeric
        : KeypadMode.alphanumeric;

    return TextFormField(
      controller: controller,
      readOnly: true,
      showCursor: true,
      enableInteractiveSelection: false,
      obscureText: obscure,
      keyboardType: keyboardType,
      enabled: enabled,
      validator: validator,
      style: TextStyle(
        color: enabled ? Colors.white : Colors.white38,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: enabled
            ? const Color(0xFF0D1A2B)
            : const Color(0xFF0D1A2B).withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF007ACC), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
      ),
      onTap: enabled
          ? () => showKeypad(
                context,
                controller: controller,
                mode: mode,
                obscureText: obscure,
                title: label.toUpperCase(),
                hint: hint,
                onCommitted: onChanged,
              )
          : null,
    );
  }
}

class _TestButton extends StatelessWidget {
  final bool testing;
  final String? status; // null=idle  ''=ok  'msg'=error
  final String label;
  final VoidCallback? onTap;

  const _TestButton({
    required this.testing,
    required this.status,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (testing) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF007ACC),
          ),
        ),
      );
    }
    if (status == '') {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.check_circle_rounded,
            color: Colors.green, size: 20),
      );
    }
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: onTap != null
              ? const Color(0xFF007ACC)
              : Colors.white24,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool ok;
  final String message;
  const _StatusChip({required this.ok, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: ok
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.redAccent.withValues(alpha: 0.1),
        border: Border.all(
          color: ok
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.redAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            color: ok ? Colors.green : Colors.redAccent,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            message,
            style: TextStyle(
              color: ok ? Colors.green : Colors.redAccent,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Raw API response box ─────────────────────────────────────────────────────

/// Muestra la respuesta cruda de la API en un cuadro monoespaciado y
/// seleccionable, para que el proveedor pueda ver el error exacto.
class _RawResponseBox extends StatelessWidget {
  final String text;
  const _RawResponseBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 14),
              const SizedBox(width: 6),
              const Text('API Response',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, color: Colors.white38, size: 12),
                    SizedBox(width: 4),
                    Text('Copy', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _OutlineBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: const Color(0xFF007ACC)),
      label: Text(label, style: const TextStyle(color: Color(0xFF007ACC), fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFF007ACC), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
