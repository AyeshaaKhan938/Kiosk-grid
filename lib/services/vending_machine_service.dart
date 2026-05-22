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
const int _kHeaderVmc = 0xAA; // VMC → App

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

  // ── Validación de respuestas ──────────────────────────────────────────────

  /// El VMC hace eco del comando con HEADER=0xAA.
  static bool _isEchoOk(Uint8List resp, int cmd) =>
      resp.length >= 5 && resp[2] == _kHeaderVmc && resp[3] == cmd;

  /// Interpreta la respuesta de Query Status (0xE1).
  static _QueryResult? _parseQueryStatus(Uint8List resp) {
    if (resp.length < 6) return null;
    if (resp[2] != _kHeaderVmc || resp[3] != _kCmdQueryStatus) return null;
    final dataLen = resp[4];
    final statusByte = resp[5];
    if (dataLen == 1) {
      if (statusByte == 0x01) return _QueryResult.deliveryOk;
      if (statusByte == 0x02) return _QueryResult.motorFault;
      if (statusByte == 0x03) return _QueryResult.sensorFault;
    }
    if (dataLen == 4) return _QueryResult.paymentComplete;
    return null;
  }

  // ── Flujo principal ───────────────────────────────────────────────────────

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

  /// Dispense via direct TTY serial.
  ///
  /// Tolerance-first flow (the strict request/echo/status loop the Reyeah
  /// docs describe was causing "delivery failed" errors after the motor
  /// successfully fired, because some board configurations don't echo back
  /// on the line we're listening on, and the 20-second status poll was
  /// holding the port open and blocking the next dispense):
  ///
  ///   1. Open the configured device (AppConfig.ttyPath, default /dev/ttyS0)
  ///      at 9600/8N1.
  ///   2. Send CMD 0x41 (delivery). If the write succeeds, the board has
  ///      the command — the motor will fire from the board's own logic.
  ///   3. Briefly listen (up to 3s) for an echo so we can surface motor or
  ///      sensor faults if the board does talk back. Missing echo is NOT
  ///      treated as failure; many boards stay silent.
  ///   4. Give the motor a few seconds to complete its turn.
  ///   5. Best-effort status query for fault detection only.
  ///   6. Close the port quickly so the next call can dispense.
  static Future<bool> _sendDeliveryViaTty({
    required int lineNumber,
    void Function(DispenseStatus)? onProgress,
  }) async {
    final path = AppConfig.ttyPath;

    bool opened = false;
    try {
      // 1. Open the port.
      try {
        opened = await TtySerial.open(path, baud: 9600);
      } on TtySerialException catch (e) {
        throw Exception(
          'Could not open $path: ${e.message}\n'
          'Use "List TTY Devices" in admin and confirm the path is correct.',
        );
      }
      if (!opened) {
        throw Exception('TtySerial.open($path) returned false.');
      }

      // 2. Send delivery frame. From this point on the motor will spin
      //    regardless of whether the board echoes back.
      await TtySerial.write(buildDeliveryFrame(lineNumber));

      // 3. Best-effort echo wait — surface obvious comms problems if any,
      //    but treat missing echo as "ok, board just doesn't echo".
      await _waitTtyResponse(
        validate: (r) => _isEchoOk(r, _kCmdDelivery),
        timeout: const Duration(seconds: 3),
      );

      // 4. Let the motor complete its turn before we close the port.
      //    Most coil/spring slots take 2–4 seconds end-to-end.
      await Future.delayed(const Duration(seconds: 4));

      // 5. One best-effort status query — only used to surface a fault
      //    code, never to call the dispense a failure.
      try {
        await TtySerial.write(buildQueryStatusFrame(lineNumber));
        await Future.delayed(const Duration(milliseconds: 400));
        final rawResp = await TtySerial.read(
          timeout: const Duration(milliseconds: 600),
        );
        if (rawResp.isNotEmpty) {
          final result = _parseQueryStatus(rawResp);
          if (result == _QueryResult.motorFault) {
            throw Exception(
              'Motor fault (code 0x02). Check the cargo lane for a jam.',
            );
          }
          if (result == _QueryResult.sensorFault) {
            throw Exception(
              'Optical sensor fault (code 0x03). Check the slot sensor.',
            );
          }
        }
      } on Exception catch (e) {
        // Re-throw real motor/sensor faults — swallow port-read noise.
        final msg = e.toString();
        if (msg.contains('Motor fault') || msg.contains('Optical sensor')) {
          rethrow;
        }
      }

      return true;
    } finally {
      if (opened) {
        // Brief flush window before closing so any in-flight bytes from the
        // board land on the file descriptor rather than getting dropped.
        await Future.delayed(const Duration(milliseconds: 200));
        try {
          await TtySerial.close();
        } catch (_) {
          // Don't let close errors mask the original outcome.
        }
      }
    }
  }

  /// Read+validate loop for the TTY path. Reads chunks until either a frame
  /// passes [validate] or [timeout] elapses.
  static Future<bool> _waitTtyResponse({
    required bool Function(Uint8List) validate,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) break;
      final chunk = await TtySerial.read(
        timeout: remaining > const Duration(milliseconds: 500)
            ? const Duration(milliseconds: 500)
            : remaining,
      );
      if (chunk.isNotEmpty && validate(chunk)) return true;
    }
    return false;
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

// ── Enum interno ──────────────────────────────────────────────────────────────
enum _QueryResult { deliveryOk, motorFault, sensorFault, paymentComplete }
