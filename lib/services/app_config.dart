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
  static const _kApiBaseUrl       = 'cfg_api_base_url';
  static const _kMachineNo        = 'cfg_machine_no';
  /// Token para el draw de lotería (por sorteo, guardado en DB del backend).
  /// Solo habilita el botón de lotería visible al cliente.
  static const _kLotteryToken     = 'cfg_lottery_token';
  /// Bearer token de gestión para los endpoints /admin/* del backend.
  /// Requerido para usar el Admin Panel (dashboard, inventario, órdenes).
  static const _kManagementToken  = 'cfg_management_token';
  static const _kAdminPin         = 'cfg_admin_pin';
  static const _kLanguage         = 'cfg_language';
  static const _kConfigured       = 'cfg_is_configured';
  // true → saltar USB serial real y simular despacho exitoso (pruebas)
  static const _kSimulateDispense = 'cfg_simulate_dispense';

  // Backend mode: 'vmscloud' | 'reyeah'
  static const _kBackendMode  = 'cfg_backend_mode';

  // Reyeah Cloud credentials
  static const _kVmBaseUrl    = 'cfg_vm_base_url';
  static const _kVmAppId      = 'cfg_vm_app_id';
  static const _kVmAppSecret  = 'cfg_vm_app_secret';
  static const _kVmMachineNo  = 'cfg_vm_machine_no';

  // TTY serial — path of the Reyeah Control Board's UART device on the tablet.
  // Default /dev/ttyS0 covers most Reyeah T1-02 mainboards; admin can override
  // via "List TTY Devices" in the admin panel if the board is on a different
  // port (ttyS1..ttyS10, or ttyUSB5 for USB-to-serial cables).
  static const _kTtyPath = 'cfg_tty_path';

  static SharedPreferences? _prefs;

  // ── Production fallbacks (baked into the APK) ─────────────────────────────
  // These values win when the .env entry is missing AND when the operator
  // never touched the field in the kiosk admin. They are the canonical values
  // for the deployed VMFS USA kiosk — the client doesn't need to enter them
  // manually after a fresh install or remote update.
  static const _prodApiBaseUrl     = 'https://cloud.vmfsusa.com/api/v1';
  static const _prodManagementToken =
      '5f938c58301641d61e730475999acb5204e92ea6d151a176c8b523c72ed7f8be';
  static const _prodMachineNo      = '866903255700003';

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
    if (stored != null && stored.isNotEmpty && !_legacyApiBaseUrls.contains(stored)) {
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
    if (stored != null && stored.isNotEmpty && !_legacyManagementTokens.contains(stored)) {
      return stored;
    }
    final envVal = dotenv.env['MANAGEMENT_TOKEN'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return _prodManagementToken;
  }

  static String get adminPin =>
      _prefs?.getString(_kAdminPin) ?? '1234';

  /// Locale code: 'en', 'es', 'fr', 'pt'
  static String get language =>
      _prefs?.getString(_kLanguage) ?? 'en';

  static bool get isConfigured =>
      _prefs?.getBool(_kConfigured) ?? false;

  /// Si es true, el despacho es simulado (sin USB serial).
  /// Activar en el Admin Panel para pruebas sin hardware conectado.
  static bool get simulateDispense =>
      _prefs?.getBool(_kSimulateDispense) ?? false;

  static Future<void> setSimulateDispense(bool value) async =>
      _prefs?.setBool(_kSimulateDispense, value);

  /// Path of the /dev/ttyS* device wired to the Reyeah Control Board.
  /// Defaults to /dev/ttyS0 — the most common port on Reyeah T1-02 boards.
  static String get ttyPath {
    final stored = _prefs?.getString(_kTtyPath);
    if (stored != null && stored.isNotEmpty) return stored;
    return dotenv.env['TTY_PATH'] ?? '/dev/ttyS0';
  }

  static Future<void> setTtyPath(String path) async =>
      _prefs?.setString(_kTtyPath, path.trim());

  /// Guarda el lottery draw token (botón de sorteo para clientes).
  static Future<void> setLotteryToken(String token) async =>
      _prefs?.setString(_kLotteryToken, token.trim());

  /// Guarda el management token (Bearer para el Admin Panel).
  static Future<void> setManagementToken(String token) async =>
      _prefs?.setString(_kManagementToken, token.trim());

  // ── Backend mode ─────────────────────────────────────────────────────────

  /// 'vmscloud' → usa el backend Laravel (vms-cloud).
  /// 'reyeah'   → usa Reyeah Cloud directamente.
  static String get backendMode =>
      _prefs?.getString(_kBackendMode) ?? 'vmscloud';

  static Future<void> setBackendMode(String mode) async =>
      _prefs?.setString(_kBackendMode, mode);

  // ── Reyeah Cloud credentials ─────────────────────────────────────────────

  static String get vmBaseUrl =>
      _prefs?.getString(_kVmBaseUrl) ??
      dotenv.env['VM_BASE_URL'] ?? 'https://4020y425z1.uicp.fun';

  static String get vmAppId =>
      _prefs?.getString(_kVmAppId) ??
      dotenv.env['VM_APP_ID'] ?? '';

  static String get vmAppSecret =>
      _prefs?.getString(_kVmAppSecret) ??
      dotenv.env['VM_APP_SECRET'] ?? '';

  static String get vmMachineNo =>
      _prefs?.getString(_kVmMachineNo) ??
      dotenv.env['VM_MACHINE_NO'] ?? '';

  static Future<void> saveReyeah({
    required String baseUrl,
    required String appId,
    required String appSecret,
    required String machineNo,
  }) async {
    final p = _prefs!;
    await Future.wait([
      p.setString(_kVmBaseUrl,   baseUrl.trim()),
      p.setString(_kVmAppId,     appId.trim()),
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
      p.setString(_kApiBaseUrl,      apiBaseUrl.trim()),
      p.setString(_kMachineNo,       machineNo.trim()),
      p.setString(_kManagementToken, managementToken.trim()),
      p.setString(_kAdminPin,        adminPin.trim()),
      p.setString(_kLanguage,        language),
      p.setBool  (_kConfigured,      true),
    ]);
  }

  static Future<void> clear() async => _prefs?.clear();

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
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

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
      final response = await http
          .post(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      // 404 = lottery not found (bad token)
      // 422 = lottery inactive or no codes (but token exists ✓)
      // 200 = success ✓
      if (response.statusCode == 404) {
        final body = jsonDecode(response.body);
        final msg  = body['message']?.toString() ?? '';
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
