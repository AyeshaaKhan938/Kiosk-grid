import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuración central de la app.
///
/// Prioridad de lectura:
///   1. SharedPreferences  ← valores guardados post-instalación (campo gana)
///   2. .env               ← fallback solo para desarrollo local
class AppConfig {
  // ── Claves SharedPreferences ─────────────────────────────────────────────
  static const _kApiBaseUrl = 'cfg_api_base_url';
  static const _kMachineNo = 'cfg_machine_no';

  /// Token para el draw de lotería (por sorteo, guardado en DB del backend).
  /// Solo habilita el botón de lotería visible al cliente.
  static const _kLotteryToken = 'cfg_lottery_token';

  /// Bearer token de gestión para los endpoints /admin/* del backend.
  /// Requerido para usar el Admin Panel (dashboard, inventario, órdenes).
  static const _kManagementToken = 'cfg_management_token';
  static const _kAdminPin = 'cfg_admin_pin';
  static const _kLanguage = 'cfg_language';
  static const _kConfigured = 'cfg_is_configured';
  // true → saltar USB serial real y simular despacho exitoso (pruebas)
  static const _kSimulateDispense = 'cfg_simulate_dispense';

  // true → background UpdateChecker auto-downloads + auto-installs new APKs
  // without any admin interaction. Kill switch lives in admin → "Auto-update"
  // tile so an operator can disable it if a bad release ever ships.
  static const _kAutoUpdate = 'cfg_auto_update';

  // true → background LogAutoUploader pushes yesterday's (and older) log
  // files to vms-cloud automatically, so the operator never has to walk
  // up to the kiosk and tap "Send to vms-cloud" by hand.
  static const _kAutoUploadLogs = 'cfg_auto_upload_logs';

  // Backend mode: 'vmscloud' | 'reyeah' | 'afen' | 'tcn'
  static const _kBackendMode = 'cfg_backend_mode';

  // AFEN Open Platform REST + VMC FunCode
  static const _kAfenBaseUrl = 'cfg_afen_base_url';
  static const _kAfenAppId = 'cfg_afen_app_id';
  static const _kAfenAppSecret = 'cfg_afen_app_secret';
  static const _kAfenDeviceId = 'cfg_afen_device_id';
  static const _kAfenVmcUrl = 'cfg_afen_vmc_url';
  static const _kAfenMachineId = 'cfg_afen_machine_id';
  static const _kAfenSignMethod = 'cfg_afen_sign_method';
  static const _kAfenBearerToken = 'cfg_afen_bearer_token';

  // TCN serial / coil control
  static const _kTcnSerialBaud = 'cfg_tcn_serial_baud';
  static const _kTcnBoardType = 'cfg_tcn_board_type'; // 'new' | 'old'
  static const _kTcnClearFaultCommand = 'cfg_tcn_clear_fault_cmd';

  // Reyeah Cloud credentials
  static const _kVmBaseUrl = 'cfg_vm_base_url';
  static const _kVmAppId = 'cfg_vm_app_id';
  static const _kVmAppSecret = 'cfg_vm_app_secret';
  static const _kVmMachineNo = 'cfg_vm_machine_no';

  // Age verification — customer scans QR, uploads ID on phone, backend verifies 18+.
  static const _kAgeVerificationEnabled = 'cfg_age_verification_enabled';
  static const _kAgeVerificationWebBase = 'cfg_age_verification_web_base';

  // TTY serial — path of the Reyeah Control Board's UART device on the tablet.
  // Default /dev/ttyS0 covers most Reyeah T1-02 mainboards; admin can override
  // via "List TTY Devices" in the admin panel if the board is on a different
  // port (ttyS1..ttyS10, or ttyUSB5 for USB-to-serial cables).
  static const _kTtyPath = 'cfg_tty_path';

  static SharedPreferences? _prefs;
  // Lift platform serial port (re-added so AppConfig.ttyPathLift resolves).
static String get ttyPathLift =>
    _prefs?.getString('cfg_tty_path_lift') ?? '/dev/ttyS8';

  // ── Production fallbacks (baked into the APK) ─────────────────────────────
  // These values win when the .env entry is missing AND when the operator
  // never touched the field in the kiosk admin. They are the canonical values
  // for the deployed VMFS USA kiosk — the client doesn't need to enter them
  // manually after a fresh install or remote update.
  static const _prodApiBaseUrl = 'https://cloud.vmfsusa.com/api/v1';
  static const _prodManagementToken =
      '5f938c58301641d61e730475999acb5204e92ea6d151a176c8b523c72ed7f8be';
  static const _prodMachineNo = '866903255700003';

  // Legacy values that older installs had saved to prefs. When we detect one
  // of these stored, we IGNORE it and use the production fallback. This
  // handles the case where an over-the-air update can't ask the customer to
  // re-type the new values.
  static const _legacyApiBaseUrls = <String>{
    'http://vms-cloud.test/api/v1',
    'https://vms-cloud.test/api/v1',
    'http://localhost/api/v1',
    'http://10.0.2.2/api/v1',
  };
  static const _legacyManagementTokens = <String>{
    // The buggy migration copied the lottery_token into management_token on
    // older installs. The known-bad value is locked out here so the .env /
    // hardcoded prod token wins on the next launch.
    '01knvsyjyjadzxrs4ma4k2mabq',
  };

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrate();
  }

  /// One-shot cleanup for known-bad values that older builds wrote to prefs.
  /// Once removed, the getters below fall through to the production fallback.
  static Future<void> _migrate() async {
    final p = _prefs!;

    // Wipe legacy API URLs (test/Laragon paths) so production wins.
    final storedApi = p.getString(_kApiBaseUrl);
    if (storedApi != null && _legacyApiBaseUrls.contains(storedApi)) {
      await p.remove(_kApiBaseUrl);
    }

    // Wipe the wrong management token that the previous buggy migration wrote.
    final storedMgmt = p.getString(_kManagementToken);
    if (storedMgmt != null && _legacyManagementTokens.contains(storedMgmt)) {
      await p.remove(_kManagementToken);
    }
  }

  // ── Getters ──────────────────────────────────────────────────────────────

  static String get apiBaseUrl {
    final stored = _prefs?.getString(_kApiBaseUrl);
    if (stored != null &&
        stored.isNotEmpty &&
        !_legacyApiBaseUrls.contains(stored)) {
      return stored;
    }
    final envVal = dotenv.env['API_BASE_URL'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return _prodApiBaseUrl;
  }

  static String get machineNo {
    final stored = _prefs?.getString(_kMachineNo);
    if (stored != null && stored.isNotEmpty) return stored;
    final envVal = dotenv.env['MACHINE_NO'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return _prodMachineNo;
  }

  static String get lotteryToken {
    final stored = _prefs?.getString(_kLotteryToken);
    if (stored != null && stored.isNotEmpty) return stored;
    return dotenv.env['LOTTERY_TOKEN'] ?? '';
  }

  /// Bearer token de gestión → habilita el Admin Panel (dashboard, inventario, órdenes).
  /// Completamente independiente del lottery draw token.
  ///
  /// Priority:
  ///   1. SharedPreferences (unless it's a known-legacy/bad value)
  ///   2. .env bundled with the APK
  ///   3. Hardcoded production fallback (so OTA updates always have the right
  ///      token even if the client never touched the admin panel).
  static String get managementToken {
    final stored = _prefs?.getString(_kManagementToken);
    if (stored != null &&
        stored.isNotEmpty &&
        !_legacyManagementTokens.contains(stored)) {
      return stored;
    }
    final envVal = dotenv.env['MANAGEMENT_TOKEN'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return _prodManagementToken;
  }

  static String get adminPin => _prefs?.getString(_kAdminPin) ?? '1234';

  /// Locale code: 'en', 'es', 'fr', 'pt'
  static String get language => _prefs?.getString(_kLanguage) ?? 'en';

  static bool get isConfigured => _prefs?.getBool(_kConfigured) ?? false;

  /// Si es true, el despacho es simulado (sin USB serial).
  /// Activar en el Admin Panel para pruebas sin hardware conectado.
  static bool get simulateDispense =>
      _prefs?.getBool(_kSimulateDispense) ?? false;

  static Future<void> setSimulateDispense(bool value) async =>
      _prefs?.setBool(_kSimulateDispense, value);

  /// Whether the background UpdateChecker should download + install new
  /// APKs automatically. Defaults to true — the kiosk runs unattended, and
  /// without auto-install the only path to a new release would be the
  /// hidden admin panel + manual tap, which defeats the point of OTA.
  /// The admin "Auto-update" tile flips this off if a bad release ever
  /// needs to be quarantined until we ship a fix.
  static bool get autoUpdate => _prefs?.getBool(_kAutoUpdate) ?? true;

  static Future<void> setAutoUpdate(bool value) async =>
      _prefs?.setBool(_kAutoUpdate, value);

  /// Whether the background LogAutoUploader should ship log files to
  /// vms-cloud on its own schedule. Defaults to true — once a kiosk is
  /// deployed there's no realistic way to fetch logs by hand, and the
  /// "Send to vms-cloud" button in admin → View Logs is for ad-hoc use
  /// when someone is already in front of the machine. For day-to-day
  /// support we want a constant trickle of logs landing in the cloud
  /// admin panel without anyone touching the kiosk.
  static bool get autoUploadLogs => _prefs?.getBool(_kAutoUploadLogs) ?? true;

  static Future<void> setAutoUploadLogs(bool value) async =>
      _prefs?.setBool(_kAutoUploadLogs, value);

  /// Path of the /dev/ttyS* device wired to the Reyeah Control Board.
  ///
  /// Resolved against the factory APK's decompiled SerialPortUtils, which
  /// branches on SDK level:
  ///   Build.VERSION.SDK_INT == 30  -> /dev/ttyS3   (Android 11)
  ///   else                         -> /dev/ttyS0
  ///
  /// Our production hardware runs Android 11, so we default to /dev/ttyS3.
  /// The admin "TTY Serial Port" tile still lets an operator override per
  /// machine if a future tablet ships a different UART mapping.
  static String get ttyPath {
    final stored = _prefs?.getString(_kTtyPath);
    if (stored != null && stored.isNotEmpty) return stored;
    return dotenv.env['TTY_PATH'] ?? '/dev/ttyS3';
  }

  static Future<void> setTtyPath(String path) async =>
      _prefs?.setString(_kTtyPath, path.trim());

  // ── Age verification ─────────────────────────────────────────────────────

  /// When true, customers must verify age (ID scan via phone QR) before
  /// entering their redemption code. Defaults to false until vms-cloud ships
  /// the matching API endpoints.
  static bool get ageVerificationEnabled =>
      _prefs?.getBool(_kAgeVerificationEnabled) ?? false;

  static Future<void> setAgeVerificationEnabled(bool value) async =>
      _prefs?.setBool(_kAgeVerificationEnabled, value);

  /// Public web base for the mobile ID-upload page (no /api/v1 suffix).
  /// Example: https://cloud.vmfsusa.com
  static String get ageVerificationWebBase {
    final stored = _prefs?.getString(_kAgeVerificationWebBase);
    if (stored != null && stored.isNotEmpty) {
      return stored.replaceAll(RegExp(r'/$'), '');
    }
    final envVal = dotenv.env['AGE_VERIFICATION_WEB_BASE'];
    if (envVal != null && envVal.isNotEmpty) {
      return envVal.replaceAll(RegExp(r'/$'), '');
    }
    // Derive from API URL: https://cloud.vmfsusa.com/api/v1 → …/cloud.vmfsusa.com
    final api = apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    if (api.endsWith('/api/v1')) {
      return api.substring(0, api.length - '/api/v1'.length);
    }
    return 'https://cloud.vmfsusa.com';
  }

  static Future<void> setAgeVerificationWebBase(String url) async =>
      _prefs?.setString(_kAgeVerificationWebBase, url.trim());

  /// Full URL encoded in the kiosk QR code for a given session.
  static String ageVerificationVerifyUrl(String sessionId) =>
      '$ageVerificationWebBase/verify?session=$sessionId';

  /// Guarda el lottery draw token (botón de sorteo para clientes).
  static Future<void> setLotteryToken(String token) async =>
      _prefs?.setString(_kLotteryToken, token.trim());

  /// Guarda el management token (Bearer para el Admin Panel).
  static Future<void> setManagementToken(String token) async =>
      _prefs?.setString(_kManagementToken, token.trim());

  // ── Backend mode ─────────────────────────────────────────────────────────

  /// 'vmscloud' → Laravel vms-cloud
  /// 'reyeah'   → Reyeah Cloud
  /// 'afen'     → AFEN Open Platform REST + FunCode VMC
  /// 'tcn'      → vms-cloud catalog + TCN serial coil dispense
  static String get backendMode =>
      _prefs?.getString(_kBackendMode) ?? 'vmscloud';

  static Future<void> setBackendMode(String mode) async =>
      _prefs?.setString(_kBackendMode, mode);

  /// UART / serial protocol for physical coil dispense.
  static String get hardwareProtocol {
    switch (backendMode) {
      case 'tcn':
        return 'tcn';
      case 'afen':
        return 'afen';
      default:
        return 'reyeah';
    }
  }

  // ── AFEN Open Platform + VMC ─────────────────────────────────────────────

  static String get afenBaseUrl =>
      _prefs?.getString(_kAfenBaseUrl) ??
      dotenv.env['AFEN_BASE_URL'] ??
      '';

  static String get afenAppId =>
      _prefs?.getString(_kAfenAppId) ?? dotenv.env['AFEN_APP_ID'] ?? '';

  static String get afenAppSecret =>
      _prefs?.getString(_kAfenAppSecret) ??
      dotenv.env['AFEN_APP_SECRET'] ??
      '';

  static String get afenDeviceId =>
      _prefs?.getString(_kAfenDeviceId) ??
      dotenv.env['AFEN_DEVICE_ID'] ??
      '';

  static String get afenVmcUrl =>
      _prefs?.getString(_kAfenVmcUrl) ?? dotenv.env['AFEN_VMC_URL'] ?? '';

  static String get afenMachineId =>
      _prefs?.getString(_kAfenMachineId) ??
      dotenv.env['AFEN_MACHINE_ID'] ??
      machineNo;

  static String get afenSignMethod =>
      _prefs?.getString(_kAfenSignMethod) ??
      dotenv.env['AFEN_SIGN_METHOD'] ??
      'hmac-sha256';

  static String get afenBearerToken =>
      _prefs?.getString(_kAfenBearerToken) ??
      dotenv.env['AFEN_BEARER_TOKEN'] ??
      '';

  static Future<void> saveAfen({
    required String baseUrl,
    required String appId,
    required String appSecret,
    required String deviceId,
    required String vmcUrl,
    required String machineId,
    String signMethod = 'hmac-sha256',
    String bearerToken = '',
  }) async {
    final p = _prefs!;
    await Future.wait([
      p.setString(_kAfenBaseUrl, baseUrl.trim()),
      p.setString(_kAfenAppId, appId.trim()),
      p.setString(_kAfenAppSecret, appSecret.trim()),
      p.setString(_kAfenDeviceId, deviceId.trim()),
      p.setString(_kAfenVmcUrl, vmcUrl.trim()),
      p.setString(_kAfenMachineId, machineId.trim()),
      p.setString(_kAfenSignMethod, signMethod.trim()),
      p.setString(_kAfenBearerToken, bearerToken.trim()),
    ]);
  }

  // ── TCN serial ────────────────────────────────────────────────────────────

  static int get tcnSerialBaud {
    final stored = _prefs?.getInt(_kTcnSerialBaud);
    if (stored != null && stored > 0) return stored;
    final env = int.tryParse(dotenv.env['TCN_SERIAL_BAUD'] ?? '');
    return env ?? 9600;
  }

  static String get tcnBoardType =>
      _prefs?.getString(_kTcnBoardType) ??
      dotenv.env['TCN_BOARD_TYPE'] ??
      'new';

  static String get tcnClearFaultCommand =>
      _prefs?.getString(_kTcnClearFaultCommand) ??
      dotenv.env['TCN_CLEAR_FAULT_CMD'] ??
      r'$$$|E|1|%%%';

  static Future<void> saveTcn({
    int? serialBaud,
    String? boardType,
    String? clearFaultCommand,
  }) async {
    final p = _prefs!;
    final ops = <Future<bool>>[];
    if (serialBaud != null) {
      ops.add(p.setInt(_kTcnSerialBaud, serialBaud));
    }
    if (boardType != null) {
      ops.add(p.setString(_kTcnBoardType, boardType.trim()));
    }
    if (clearFaultCommand != null) {
      ops.add(p.setString(_kTcnClearFaultCommand, clearFaultCommand.trim()));
    }
    if (ops.isNotEmpty) await Future.wait(ops);
  }

  // ── Reyeah Cloud credentials ─────────────────────────────────────────────

  static String get vmBaseUrl =>
      _prefs?.getString(_kVmBaseUrl) ??
      dotenv.env['VM_BASE_URL'] ??
      'https://4020y425z1.uicp.fun';

  static String get vmAppId =>
      _prefs?.getString(_kVmAppId) ?? dotenv.env['VM_APP_ID'] ?? '';

  static String get vmAppSecret =>
      _prefs?.getString(_kVmAppSecret) ?? dotenv.env['VM_APP_SECRET'] ?? '';

  static String get vmMachineNo =>
      _prefs?.getString(_kVmMachineNo) ?? dotenv.env['VM_MACHINE_NO'] ?? '';

  static Future<void> saveReyeah({
    required String baseUrl,
    required String appId,
    required String appSecret,
    required String machineNo,
  }) async {
    final p = _prefs!;
    await Future.wait([
      p.setString(_kVmBaseUrl, baseUrl.trim()),
      p.setString(_kVmAppId, appId.trim()),
      p.setString(_kVmAppSecret, appSecret.trim()),
      p.setString(_kVmMachineNo, machineNo.trim()),
    ]);
  }

  // ── Setters ──────────────────────────────────────────────────────────────

  static Future<void> save({
    required String apiBaseUrl,
    required String machineNo,
    required String managementToken,
    required String adminPin,
    required String language,
  }) async {
    final p = _prefs!;
    await Future.wait([
      p.setString(_kApiBaseUrl, apiBaseUrl.trim()),
      p.setString(_kMachineNo, machineNo.trim()),
      p.setString(_kManagementToken, managementToken.trim()),
      p.setString(_kAdminPin, adminPin.trim()),
      p.setString(_kLanguage, language),
      p.setBool(_kConfigured, true),
    ]);
  }

  static Future<void> clear() async {
    final p = _prefs ?? await SharedPreferences.getInstance();
    await p.remove(_kConfigured);
    await p.clear();
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Test de conexión al backend ──────────────────────────────────────────

  /// Hace un GET a [url]/api/v1/health o simplemente al [url] base
  /// para verificar que el servidor es alcanzable.
  ///
  /// Devuelve null si todo está bien, o un mensaje de error si falla.
  static Future<String?> testConnection(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/$'), '');
    if (clean.isEmpty) return 'URL cannot be empty';

    try {
      // Intentamos el endpoint de slots con un machineNo ficticio.
      // Si el servidor responde (cualquier HTTP) → está vivo.
      final uri = Uri.parse('$clean/machines/__ping__/slots');
      final response = await http.get(uri, headers: {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 8));

      // 404 significa que el servidor respondió (máquina no existe, pero la
      // API está arriba). Cualquier otra respuesta HTTP también es válida.
      if (response.statusCode > 0) return null;
      return 'Server returned unexpected status ${response.statusCode}';
    } on FormatException {
      return 'Invalid URL format';
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Failed host')) {
        return 'Cannot reach server. Check URL and network.';
      }
      if (msg.contains('TimeoutException')) {
        return 'Connection timed out. Server may be offline.';
      }
      return 'Connection failed: $msg';
    }
  }

  /// Verifica que el token de lotería es válido llamando al draw endpoint.
  /// Devuelve null si el token existe (aunque no haya códigos),
  /// o un mensaje de error si el token no existe.
  static Future<String?> testLotteryToken(String baseUrl, String token) async {
    if (token.trim().isEmpty) return 'Token cannot be empty';
    final clean = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    try {
      final uri = Uri.parse('$clean/product-lottery-draw/${token.trim()}');
      final response = await http.post(uri, headers: {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 8));

      // 404 = lottery not found (bad token)
      // 422 = lottery inactive or no codes (but token exists ✓)
      // 200 = success ✓
      if (response.statusCode == 404) {
        final body = jsonDecode(response.body);
        final msg = body['message']?.toString() ?? '';
        if (msg.toLowerCase().contains('lottery')) {
          return 'Token not found. Check the cPanel.';
        }
      }
      if (response.statusCode == 200 || response.statusCode == 422) {
        return null; // token válido
      }
      return 'Unexpected response (${response.statusCode})';
    } catch (_) {
      return 'Could not verify token. Check connection first.';
    }
  }
}
