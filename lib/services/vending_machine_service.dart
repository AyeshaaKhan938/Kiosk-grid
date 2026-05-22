import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'tty_serial.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Control Board Communication API — Guangzhou Reyeah Technology
//
// UART serial: 9600 bps, 8 data bits, 1 stop bit, no parity, no flow control.
//
// Trama (frame):
//   [0xFF ADDR] [0x00 FRAME_NUM] [HEADER] [CMD] [DATA_LEN] [DATA...] [CHK]
//
//   HEADER: 0x55 = App→VMC   /   0xAA = VMC→App
//   CHK = suma acumulada de (HEADER + CMD + DATA_LEN + DATA[0..n]) & 0xFF
//         — excluye ADDR (0xFF) y FRAME_NUM (0x00)
// ─────────────────────────────────────────────────────────────────────────────

// ── Bytes fijos de la trama ───────────────────────────────────────────────────
const int _kAddrByte  = 0xFF;
const int _kFrameNum  = 0x00;
const int _kHeaderApp = 0x55; // App → VMC
// _kHeaderVmc (0xAA) was the response-side header; removed alongside the
// read+status-query path. Restore from git history if/when the JNI is
// patched and we re-enable response parsing.

// ── Comandos ──────────────────────────────────────────────────────────────────
const int _kCmdDelivery    = 0x41; // Despachar producto
const int _kCmdQueryStatus = 0xE1; // Consultar estado
const int _kCmdClearFault  = 0xA2; // Limpiar fallo

/// Estados del flujo de despacho.
enum DispenseStatus { sending, waitingConfirm, success, error }

/// Resultado final del despacho.
class DispenseResult {
  final DispenseStatus status;
  final String? errorMessage;
  const DispenseResult({required this.status, this.errorMessage});
}

/// Servicio de comunicación con el Control Board de la vending machine.
///
/// Responsabilidades:
///   1. Enviar tramas binarias al VMC vía USB serial (UART 9600/8N1).
///   2. Reportar el resultado al backend Laravel para trazabilidad.
///
/// Para pruebas sin hardware: pasar `simulateSuccess: true`
/// (controlado desde AppConfig.simulateDispense).
class VendingMachineService {
  static String get _baseUrl => AppConfig.apiBaseUrl;

  // ── Single-flight gate ────────────────────────────────────────────────────
  // Only ONE dispense can be in flight at a time, and a fresh dispense can't
  // start until the previous one has cooled down for [_kCooldownMs]. Two
  // reasons:
  //
  //  1. The previous code allowed back-to-back dispenses to overlap on the
  //     native TTY channel, racing against the close() call that follows
  //     dispense N while dispense N+1 was already trying to open. That race
  //     was a major contributor to the post-vend SIGSEGV.
  //
  //  2. The Reyeah board needs a brief idle window between commands or it
  //     ignores the second frame. The cooldown also gives Android's audio
  //     subsystem (which can be triggered by the motor relay click) time
  //     to settle, which on a few of the cheaper OEM tablets was throwing
  //     ANRs and killing the activity.
  static Future<DispenseResult>? _inFlight;
  static DateTime? _lastDispenseEndedAt;
  static const _kCooldownMs = 1500;

  // ── Constructor de tramas ─────────────────────────────────────────────────

  /// Construye la trama binaria para cualquier comando.
  ///
  /// CHK = (HEADER + CMD + dataLen + sum(data)) & 0xFF
  /// Excluye ADDR (0xFF) y FRAME_NUM (0x00) del cálculo según el protocolo.
  static Uint8List _buildFrame(int cmd, List<int> data) {
    final int dataLen = data.length;
    int chk = (_kHeaderApp + cmd + dataLen) & 0xFF;
    for (final b in data) {
      chk = (chk + b) & 0xFF;
    }
    return Uint8List.fromList([
      _kAddrByte, _kFrameNum, _kHeaderApp, cmd, dataLen,
      ...data,
      chk,
    ]);
  }

  // ── Tramas específicas ────────────────────────────────────────────────────

  /// CMD 0x41 — Despachar slot [slot], cantidad [qty] (default 1).
  /// Frame: FF | 00 | 55 | 41 | 02 | slot | qty | CHK
  static Uint8List buildDeliveryFrame(int slot, {int qty = 1}) =>
      _buildFrame(_kCmdDelivery, [slot & 0xFF, qty & 0xFF]);

  /// CMD 0xE1 — Consultar estado de la máquina.
  static Uint8List buildQueryStatusFrame(int slot, {int qty = 1}) =>
      _buildFrame(_kCmdQueryStatus, [slot & 0xFF, qty & 0xFF]);

  /// CMD 0xA2 — Limpiar fallo.
  static Uint8List buildClearFaultFrame() =>
      _buildFrame(_kCmdClearFault, [0xFF]);

  // ── Flujo principal ───────────────────────────────────────────────────────
  //
  // Response-parsing helpers (_isEchoOk, _parseQueryStatus, _QueryResult)
  // were removed alongside the read+status-query path that was crashing
  // the activity. If/when the JNI close is patched and we re-enable
  // reads, restore them from git history.

  /// Internal single-flight gate. If another dispense is already running we
  /// await its result before starting; if one just finished we sleep the
  /// remaining cooldown so the next request hits a quiet TTY channel and a
  /// quiet motor relay.
  static Future<DispenseResult> _withDispenseGate(
    Future<DispenseResult> Function() body,
  ) async {
    // Chain onto any in-flight dispense rather than running concurrently.
    // We intentionally only OBSERVE the previous result — we don't reuse
    // it — so the caller never gets stale data from another flow.
    while (_inFlight != null) {
      try {
        await _inFlight;
      } catch (_) {
        // Previous dispense errored out; that's its caller's problem,
        // not ours.
      }
    }

    // Honor the post-dispense cooldown window.
    final ended = _lastDispenseEndedAt;
    if (ended != null) {
      final waited = DateTime.now().difference(ended).inMilliseconds;
      if (waited < _kCooldownMs) {
        await Future.delayed(Duration(milliseconds: _kCooldownMs - waited));
      }
    }

    final completer = body();
    _inFlight = completer;
    try {
      final result = await completer;
      return result;
    } finally {
      _lastDispenseEndedAt = DateTime.now();
      if (identical(_inFlight, completer)) _inFlight = null;
    }
  }

  /// Despacha el producto del slot [lineNumber] y reporta el resultado
  /// al backend Laravel.
  ///
  /// [simulateSuccess] = true → omite el hardware (pruebas sin máquina).
  static Future<DispenseResult> dispenseProduct({
    required int lineNumber,
    required String lotteryCode,
    required String machineNo,
    bool simulateSuccess = false,
    String paymentMethod = 'cash',
    String? paymentReference,
    void Function(DispenseStatus)? onProgress,
  }) {
    return _withDispenseGate(() => _dispenseProductImpl(
          lineNumber:       lineNumber,
          lotteryCode:      lotteryCode,
          machineNo:        machineNo,
          simulateSuccess:  simulateSuccess,
          paymentMethod:    paymentMethod,
          paymentReference: paymentReference,
          onProgress:       onProgress,
        ));
  }

  static Future<DispenseResult> _dispenseProductImpl({
    required int lineNumber,
    required String lotteryCode,
    required String machineNo,
    bool simulateSuccess = false,
    String paymentMethod = 'cash',
    String? paymentReference,
    void Function(DispenseStatus)? onProgress,
  }) async {
    onProgress?.call(DispenseStatus.sending);

    bool physicalSuccess = false;
    String errorMsg = '';

    try {
      if (simulateSuccess) {
        // ── Modo simulación ──────────────────────────────────────────────
        final frame = buildDeliveryFrame(lineNumber);
        assert(frame.isNotEmpty);
        await Future.delayed(const Duration(milliseconds: 1200));
        physicalSuccess = true;
      } else {
        // ── Modo real (TTY serial — /dev/ttyS* directly via JNI) ─────────
        //
        // Confirmed against the factory APK: the Reyeah Control Board on
        // this hardware is wired to the tablet's UART pins, NOT through a
        // USB-to-serial bridge. usb_serial enumeration sees nothing because
        // the device isn't on USB at all.
        physicalSuccess = await _sendDeliveryViaTty(
          lineNumber: lineNumber,
          onProgress: onProgress,
        );
        if (!physicalSuccess) errorMsg = 'VMC did not confirm delivery.';
      }
    } catch (e) {
      errorMsg = e.toString();
      physicalSuccess = false;
    }

    onProgress?.call(
      physicalSuccess ? DispenseStatus.waitingConfirm : DispenseStatus.error,
    );

    await _reportDispense(
      lotteryCode: lotteryCode,
      machineNo: machineNo,
      lineNumber: lineNumber,
      success: physicalSuccess,
      error: physicalSuccess ? null : errorMsg,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
    );

    return DispenseResult(
      status: physicalSuccess ? DispenseStatus.success : DispenseStatus.error,
      errorMessage: physicalSuccess ? null : errorMsg,
    );
  }

  // ── Admin / hardware test ─────────────────────────────────────────────────

  /// Fires a real UART delivery for [lineNumber] without creating an Order
  /// or reporting to the backend. Used by the kiosk admin panel to verify
  /// the Reyeah control board is wired and a specific slot's motor works.
  ///
  /// Returns a [DispenseResult] — `success` means the motor confirmed delivery,
  /// `error` means the VMC reported a fault or did not respond.
  static Future<DispenseResult> testDispenseSlot(int lineNumber) {
    return _withDispenseGate(() => _testDispenseSlotImpl(lineNumber));
  }

  static Future<DispenseResult> _testDispenseSlotImpl(int lineNumber) async {
    if (kIsWeb) {
      return const DispenseResult(
        status: DispenseStatus.error,
        errorMessage:
            'TTY serial only works on Android. Install the APK on the tablet '
            'and run this test there.',
      );
    }

    // Honor the same Simulate Dispense toggle the customer flow uses.
    // When the operator wants to verify the app's flow / progress dialog
    // without firing any real hardware (e.g. on a bench tablet, or while
    // diagnosing a TTY driver issue), flipping the admin toggle now
    // bypasses TTY entirely for the test path too.
    if (AppConfig.simulateDispense) {
      await Future.delayed(const Duration(seconds: 5));
      return const DispenseResult(status: DispenseStatus.success);
    }

    try {
      final ok = await _sendDeliveryViaTty(
        lineNumber: lineNumber,
        onProgress: null,
      );
      return DispenseResult(
        status: ok ? DispenseStatus.success : DispenseStatus.error,
        errorMessage: ok ? null : 'VMC did not confirm delivery.',
      );
    } on MissingPluginException {
      return const DispenseResult(
        status: DispenseStatus.error,
        errorMessage:
            'TTY serial plugin not available on this platform. Test from the '
            'physical Android tablet, not Chrome.',
      );
    } catch (e) {
      return DispenseResult(
        status: DispenseStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Comunicación TTY serial real (/dev/ttyS* via JNI) ───────────────────
  //
  // Confirmed against the factory APK that the Reyeah Control Board is
  // wired to the tablet's UART pins, not USB. This path uses the
  // android-serialport-api bridge in TtySerialChannel.kt.

  /// Dispense via direct TTY serial — factory-pattern flow.
  ///
  /// Implementation mirrors factory.apk's `SerialPortUtils.onSaleSend()`
  /// (confirmed via jadx decompile). Same ordering, same protocol,
  /// same singleton-reuse model.
  ///
  ///   1. openSerialPort(path, 9600) — channel reuses the existing
  ///      session if path + baud match; otherwise a fresh open with
  ///      a residual-byte drain. A persistent ReadThread on the
  ///      Kotlin side starts pumping inbound bytes into an in-process
  ///      queue.
  ///   2. Write delivery frame (CMD 0x41). Motor fires from the
  ///      board's own logic.
  ///   3. Best-effort drain of the rx queue (600 ms window). Bytes
  ///      come from the in-process queue, never from a native fd —
  ///      so this can't race with close. The motor fires whether
  ///      the board echoes or not.
  ///   4. Wait 5 s for the motor to physically complete.
  ///   5. NO close here. The singleton stays open for the next
  ///      dispense (factory pattern: open once, reuse forever). The
  ///      port only closes on explicit admin teardown / app exit.
  static Future<bool> _sendDeliveryViaTty({
    required int lineNumber,
    void Function(DispenseStatus)? onProgress,
  }) async {
    final path = AppConfig.ttyPath;

    // 1. Open. The outer dispenseProduct catches any throw here.
    try {
      final opened = await TtySerial.open(path, baud: 9600);
      if (!opened) {
        throw Exception('TtySerial.open($path) returned false.');
      }
    } on TtySerialException catch (e) {
      throw Exception(
        'Could not open $path: ${e.message}\n'
        'Use "List TTY Devices" in admin and confirm the path is correct.',
      );
    }

    // 2. Write the delivery frame.
    await TtySerial.write(buildDeliveryFrame(lineNumber));

    // 3. Drain the inbound queue (echo / status from the board).
    //    Bytes come from the channel's in-process queue populated by
    //    the persistent ReadThread, not from a direct native read —
    //    so this can never race with close(). Best-effort: motor
    //    fires regardless of echo.
    try {
      await TtySerial.read(timeout: const Duration(milliseconds: 600));
    } catch (_) {
      // A read failure here is fine; we already wrote the command.
    }

    // 4. Wait out the motor turn. 5 s covers every coil/spring slot we
    //    have field data on.
    await Future.delayed(const Duration(seconds: 5));

    // 5. Intentionally NO close — singleton stays open for the next
    //    dispense (factory pattern). Closing happens via explicit
    //    admin teardown / app shutdown / TTY path change.
    return true;
  }

  // ── Reporte al backend Laravel ────────────────────────────────────────────

  static Future<void> _reportDispense({
    required String lotteryCode,
    required String machineNo,
    required int lineNumber,
    required bool success,
    String? error,
    String paymentMethod = 'cash',
    String? paymentReference,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/dispense'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'lottery_code':   lotteryCode,
              'machine_no':     machineNo,
              'line_number':    lineNumber,
              'status':         success ? 'success' : 'failed',
              'payment_method': paymentMethod,
              if (paymentReference != null)
                'payment_reference': paymentReference,
              if (error != null) 'error': error,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best-effort: no bloqueamos la UX si falla la red.
    }
  }
}
