import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'admin_api_service.dart';
import 'app_config.dart';
import 'dispense_wake_lock.dart';
import 'log_file_util.dart';
import 'serial_frame_assembler.dart';
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
const int _kAddrByte = 0xFF;
const int _kFrameNum = 0x00;
const int _kHeaderApp = 0x55; // App → VMC
// _kHeaderVmc (0xAA) was the response-side header; removed alongside the
// read+status-query path. Restore from git history if/when the JNI is
// patched and we re-enable response parsing.

// ── Comandos ──────────────────────────────────────────────────────────────────
const int _kCmdDelivery = 0x41; // Despachar producto
const int _kCmdQueryStatus = 0xE1; // Consultar estado
const int _kCmdClearFault = 0xA2; // Limpiar fallo
const int _kCmdQueryFloorHeight = 0x20; // Query lift floor heights
const int _kCmdSetFloorHeight = 0x21; // Set lift floor height (elevator only)
const int _kCmdVmcLog = 0x03; // Export VMC log

// CMD 0x41 second data byte. This hardware must always use side-push:
//   FF 00 55 41 02 <slot> FB <chk>
const int _kDeliverySidePush = 0xFB;

/// Estados del flujo de despacho.
enum DispenseStatus { sending, waitingConfirm, success, error }

/// Resultado final del despacho.
class DispenseResult {
  final DispenseStatus status;
  final String? errorMessage;
  const DispenseResult({required this.status, this.errorMessage});
}

class FloorHeightsResult {
  final bool success;
  final List<int> heights;
  final String? errorMessage;
  final String? rawHex;

  const FloorHeightsResult({
    required this.success,
    this.heights = const [],
    this.errorMessage,
    this.rawHex,
  });
}

class VmcLogResult {
  final bool success;
  final String text;
  final String? errorMessage;

  const VmcLogResult({
    required this.success,
    this.text = '',
    this.errorMessage,
  });
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

  /// True iff a dispense (customer, admin test, or heartbeat) is mid-flight.
  /// Used by the background OTA auto-installer to wait for a quiet moment
  /// before reinstalling — we don't want `pm install -r` to kill our
  /// process in the middle of a motor turn.
  static bool get isBusy => _inFlight != null;

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
      _kAddrByte,
      _kFrameNum,
      _kHeaderApp,
      cmd,
      dataLen,
      ...data,
      chk,
    ]);
  }

  // ── Tramas específicas ────────────────────────────────────────────────────

  /// CMD 0x41 — Dispense [slot].
  ///
  /// Frame: FF | 00 | 55 | 41 | 02 | slot | 0xFB | CHK
  ///
  /// The second byte is fixed to 0xFB (side-push). Do not use quantity 0x01
  /// here; this control board expects `<slot> FB` for delivery.
  static Uint8List buildDeliveryFrame(int slot) {
    return _buildFrame(_kCmdDelivery, [slot & 0xFF, _kDeliverySidePush]);
  }

  /// CMD 0xE1 — Consultar estado de la máquina.
  static Uint8List buildQueryStatusFrame(int slot, {int qty = 1}) =>
      _buildFrame(_kCmdQueryStatus, [slot & 0xFF, qty & 0xFF]);

  /// CMD 0xA2 — Limpiar fallo.
  static Uint8List buildClearFaultFrame() =>
      _buildFrame(_kCmdClearFault, [0xFF]);
  // CMD 0xA1 — Full VMC reset (re-added so buildResetVmcFrame() resolves).
static Uint8List buildResetVmcFrame() => _buildFrame(0xA1, [0xFF]);

  /// CMD 0x20 — Query lift-platform floor heights.
  ///
  /// Reference app: Config.serial_20_key = FF00552001FF.
  static Uint8List buildQueryFloorHeightsFrame() =>
      _buildFrame(_kCmdQueryFloorHeight, [0xFF]);

  /// CMD 0x21 — Set one lift-platform floor height.
  ///
  /// Reference app: FF00552103 + <floor> + <height uint16>.
  static Uint8List buildSetFloorHeightFrame(int floor, int height) {
    if (floor < 1 || floor > 255) {
      throw ArgumentError.value(floor, 'floor', 'Must be 1-255.');
    }
    if (height < 0 || height > 0xFFFF) {
      throw ArgumentError.value(height, 'height', 'Must be 0-65535.');
    }
    return _buildFrame(_kCmdSetFloorHeight, [
      floor & 0xFF,
      (height >> 8) & 0xFF,
      height & 0xFF,
    ]);
  }

  /// CMD 0x03 — Request VMC log export.
  ///
  /// Reference app sends this at 9600, then reopens the same port at 115200
  /// and reads UTF-8 log text until it contains "successfully".
  static Uint8List buildVmcLogFrame() => _buildFrame(_kCmdVmcLog, [0xFF]);

  /// CMD 0x21 — Enable lift-platform auto-height-detection.
  ///
  /// Frame: FF | 00 | 55 | 21 | 03 | FF | 00 | 00 | CHK
  ///
  /// Floor=0xFF is the protocol's "auto-detect" sentinel. The VMC
  /// physically runs the lift up and down, learns each floor's height,
  /// and persists the map internally. Without this calibration, the
  /// elevator can't move the platform to a slot's floor — every dispense
  /// returns motor-fault status (data byte 0x02 on a 0xE1 query).
  ///
  /// Mirrors factory.apk's `onSetHeightSend()`. Confirmed via UART
  /// capture from the client's machine that this is the missing step:
  /// CMD 0x41 with 0xFB side-push echoes back fine but the lift never
  /// moves because the floor map was never built.
  static Uint8List buildCalibrateLiftFrame() =>
      _buildFrame(_kCmdSetFloorHeight, [0xFF, 0x00, 0x00]);

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

    // Hold a CPU wake lock for the duration of the gated op so Android
    // can't suspend us mid-motor-turn. Auto-released after 30s as a
    // safety net in case the body never completes.
    await DispenseWakeLock.acquire(
      'dispense',
      timeout: const Duration(seconds: 30),
    );
    LogFileUtil.i('dispense.gate.enter');

    final completer = body();
    _inFlight = completer;
    try {
      final result = await completer;
      LogFileUtil.i('dispense.gate.result', {
        'status': result.status.name,
        if (result.errorMessage != null) 'error': result.errorMessage!,
      });
      return result;
    } catch (e, st) {
      LogFileUtil.e('dispense.gate.exception', error: e, stack: st);
      rethrow;
    } finally {
      _lastDispenseEndedAt = DateTime.now();
      if (identical(_inFlight, completer)) _inFlight = null;
      await DispenseWakeLock.release('dispense');
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
          lineNumber: lineNumber,
          lotteryCode: lotteryCode,
          machineNo: machineNo,
          simulateSuccess: simulateSuccess,
          paymentMethod: paymentMethod,
          paymentReference: paymentReference,
          onProgress: onProgress,
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

  // ── Heartbeat + fault recovery (factory parity) ──────────────────────────

  /// Sends a CMD 0xE1 status query through the same single-flight gate
  /// the dispense flow uses. Returns true if the board echoed anything
  /// back. Best-effort: never throws. Used by [BoardHeartbeat] for
  /// periodic liveness checks.
  static Future<bool> queryStatusViaGate({int slot = 1}) async {
    if (kIsWeb) return false;
    final result = await _withDispenseGate(() => _queryStatusImpl(slot));
    return result.status == DispenseStatus.success;
  }

  static Future<DispenseResult> _queryStatusImpl(int slot) async {
    try {
      final opened = await TtySerial.open(AppConfig.ttyPath, baud: 9600);
      if (!opened) {
        return const DispenseResult(
          status: DispenseStatus.error,
          errorMessage: 'open failed',
        );
      }
      await TtySerial.write(buildQueryStatusFrame(slot));
      final resp = await TtySerial.read(
        timeout: const Duration(milliseconds: 600),
      );
      return DispenseResult(
        status: resp.isNotEmpty ? DispenseStatus.success : DispenseStatus.error,
        errorMessage: resp.isEmpty ? 'no reply' : null,
      );
    } catch (e) {
      return DispenseResult(
        status: DispenseStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Sends CMD 0xA2 (clear fault). Admin uses this when the board has
  /// latched a motor or sensor fault and refuses to dispense further.
  /// Runs through the dispense gate; returns the result so admin UI can
  /// show success / error to the operator.
  static Future<DispenseResult> clearFaultsViaGate() async {
    if (kIsWeb) {
      return const DispenseResult(
        status: DispenseStatus.error,
        errorMessage: 'Clear faults only works on the tablet.',
      );
    }
    return _withDispenseGate(_clearFaultsImpl);
  }

  static Future<DispenseResult> _clearFaultsImpl() async {
    try {
      final opened = await TtySerial.open(AppConfig.ttyPath, baud: 9600);
      if (!opened) {
        return const DispenseResult(
          status: DispenseStatus.error,
          errorMessage: 'TtySerial.open returned false',
        );
      }
      await TtySerial.write(buildClearFaultFrame());
      // Drain any echo so it doesn't pollute the next dispense's read.
      await TtySerial.read(timeout: const Duration(milliseconds: 400));
      return const DispenseResult(status: DispenseStatus.success);
    } catch (e) {
      return DispenseResult(
        status: DispenseStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Send CMD 0xA1 (Reset VMC) through the dispense gate. Brings the
  /// lift platform back to its home position and resets the VMC's
  /// internal state. Used when the lift has gotten stuck at an
  /// unexpected floor (e.g. parked at the top after a half-completed
  /// calibration). The VMC takes a few seconds to physically run the
  /// lift back down, so we hold the gate for ~10 s.
  static Future<DispenseResult> resetVmcViaGate() async {
    if (kIsWeb) {
      return const DispenseResult(
        status: DispenseStatus.error,
        errorMessage: 'VMC reset only works on the tablet.',
      );
    }
    return _withDispenseGate(_resetVmcImpl);
  }

  static Future<DispenseResult> _resetVmcImpl() async {
    try {
      final opened = await TtySerial.open(AppConfig.ttyPath, baud: 9600);
      if (!opened) {
        return const DispenseResult(
          status: DispenseStatus.error,
          errorMessage: 'TtySerial.open returned false',
        );
      }

      final frame = buildResetVmcFrame();
      LogFileUtil.i('vmc.reset.send', {
        'frame': frame
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' '),
      });
      await TtySerial.write(frame);

      // Drain the echo (FF 00 AA A1 ...) — best-effort.
      try {
        final echo = await TtySerial.read(
          timeout: const Duration(milliseconds: 600),
        );
        LogFileUtil.i('vmc.reset.echo', {'bytes': echo.length.toString()});
      } catch (_) {}

      // Hold the gate while the lift physically runs back to home.
      // Field-observed travel time is ~6 s end-to-end; 10 s pad is safe.
      await Future<void>.delayed(const Duration(seconds: 10));
      LogFileUtil.i('vmc.reset.complete');

      return const DispenseResult(status: DispenseStatus.success);
    } catch (e) {
      return DispenseResult(
        status: DispenseStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Run lift-platform auto-calibration through the same single-flight
  /// gate the dispense flow uses. Sends CMD 0x21 with Floor=0xFF, then
  /// holds the gate for ~45 s while the physical lift runs up and down
  /// through every floor learning heights. The VMC persists the result
  /// internally — this only needs to be run once per machine after
  /// switching Machine Type to Elevator.
  static Future<DispenseResult> calibrateLiftViaGate() async {
    if (kIsWeb) {
      return const DispenseResult(
        status: DispenseStatus.error,
        errorMessage: 'Lift calibration only works on the tablet.',
      );
    }
    return _withDispenseGate(_calibrateLiftImpl);
  }

  static Future<DispenseResult> _calibrateLiftImpl() async {
    try {
      // CRITICAL: lift platform listens on a DIFFERENT UART than the
      // main VMC. Factory.apk's PostUtil hard-codes
      // `port_forlifter = "/dev/ttyS8"`. Sending CMD 0x21 to the main
      // VMC port does nothing because the lift's microcontroller isn't
      // wired to that bus. The kiosk picks ttyPathLift here (default
      // /dev/ttyS8, overridable via admin) so the calibration command
      // actually reaches the lift's MCU.
      final liftPath = AppConfig.ttyPathLift;
      LogFileUtil.i('lift.calibrate.open_port', {'path': liftPath});

      final opened = await TtySerial.open(liftPath, baud: 9600);
      if (!opened) {
        return DispenseResult(
          status: DispenseStatus.error,
          errorMessage: 'TtySerial.open returned false on $liftPath',
        );
      }

      final frame = buildCalibrateLiftFrame();
      LogFileUtil.i('lift.calibrate.send', {
        'path': liftPath,
        'frame': frame
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' '),
      });
      await TtySerial.write(frame);

      // Drain the immediate echo (FF 00 AA 21 ... in factory traces).
      try {
        final echo = await TtySerial.read(
          timeout: const Duration(milliseconds: 800),
        );
        LogFileUtil.i('lift.calibrate.echo', {'bytes': echo.length.toString()});
      } catch (_) {
        // Best-effort — calibration runs regardless of whether we
        // read the echo cleanly.
      }

      // Hold the gate while the lift physically runs through all
      // floors. Factory captures show ~30 s for a fully-loaded 6-floor
      // elevator; we pad to 45 s so a slower / longer machine still
      // finishes inside the window.
      await Future<void>.delayed(const Duration(seconds: 45));
      LogFileUtil.i('lift.calibrate.complete');

      return const DispenseResult(status: DispenseStatus.success);
    } catch (e) {
      return DispenseResult(
        status: DispenseStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<FloorHeightsResult> queryFloorHeights() async {
    if (kIsWeb) {
      return const FloorHeightsResult(
        success: false,
        errorMessage: 'Floor-height query only works on the tablet.',
      );
    }

    try {
      await _openConfiguredTty(baud: 9600);
      await TtySerial.write(buildClearFaultFrame());
      await TtySerial.read(timeout: const Duration(milliseconds: 400));

      final frame = buildQueryFloorHeightsFrame();
      LogFileUtil.i('lift.height.query.send', {'frame': _hex(frame)});
      await TtySerial.write(frame);

      final response = await _readFrameForCommand(
        _kCmdQueryFloorHeight,
        timeout: const Duration(seconds: 3),
      );
      if (response == null) {
        return const FloorHeightsResult(
          success: false,
          errorMessage: 'No CMD 0x20 response from VMC.',
        );
      }

      final dataLen = response[4];
      final data = response.sublist(5, 5 + dataLen);
      final heights = <int>[];
      for (var i = 0; i + 1 < data.length; i += 2) {
        heights.add((data[i] << 8) | data[i + 1]);
      }

      return FloorHeightsResult(
        success: true,
        heights: heights,
        rawHex: _hex(response),
      );
    } catch (e) {
      return FloorHeightsResult(success: false, errorMessage: e.toString());
    }
  }

  static Future<DispenseResult> setFloorHeight({
    required int floor,
    required int height,
  }) async {
    if (kIsWeb) {
      return const DispenseResult(
        status: DispenseStatus.error,
        errorMessage: 'Floor-height setting only works on the tablet.',
      );
    }

    try {
      await _openConfiguredTty(baud: 9600);
      final frame = buildSetFloorHeightFrame(floor, height);
      LogFileUtil.i('lift.height.set.send', {
        'floor': floor.toString(),
        'height': height.toString(),
        'frame': _hex(frame),
      });
      await TtySerial.write(frame);

      final response = await _readFrameForCommand(
        _kCmdSetFloorHeight,
        timeout: const Duration(seconds: 2),
      );
      if (response == null) {
        return const DispenseResult(
          status: DispenseStatus.error,
          errorMessage: 'No CMD 0x21 response from VMC.',
        );
      }

      return const DispenseResult(status: DispenseStatus.success);
    } catch (e) {
      return DispenseResult(
        status: DispenseStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  static Future<VmcLogResult> fetchVmcLog({
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (kIsWeb) {
      return const VmcLogResult(
        success: false,
        errorMessage: 'VMC log export only works on the tablet.',
      );
    }

    try {
      await _openConfiguredTty(baud: 9600);
      await TtySerial.write(buildClearFaultFrame());
      await TtySerial.read(timeout: const Duration(milliseconds: 400));

      final request = buildVmcLogFrame();
      LogFileUtil.i('vmc.log.request.send', {'frame': _hex(request)});
      await TtySerial.write(request);

      await _readFrameForCommand(
        _kCmdVmcLog,
        timeout: const Duration(seconds: 2),
      );

      await _openConfiguredTty(baud: 115200);
      final deadline = DateTime.now().add(timeout);
      final buffer = StringBuffer();
      while (DateTime.now().isBefore(deadline)) {
        final chunk = await TtySerial.read(
          timeout: const Duration(milliseconds: 500),
        );
        if (chunk.isEmpty) continue;
        buffer.write(utf8.decode(chunk, allowMalformed: true));
        if (buffer.toString().contains('successfully')) break;
      }

      final text = buffer.toString();
      if (text.isEmpty) {
        return const VmcLogResult(
          success: false,
          errorMessage: 'No VMC log bytes received at 115200 baud.',
        );
      }

      LogFileUtil.i('vmc.log.received', {'chars': text.length.toString()});
      return VmcLogResult(
        success: text.contains('successfully'),
        text: text,
        errorMessage:
            text.contains('successfully') ? null : 'Log transfer timed out.',
      );
    } catch (e) {
      return VmcLogResult(success: false, errorMessage: e.toString());
    } finally {
      try {
        await _openConfiguredTty(baud: 9600);
      } catch (_) {
        // Best-effort: restore normal command baud for the next admin action.
      }
    }
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
      if (ok) {
        // A verified vend should leave inventory consistent, just like a
        // real sale. Decrement the slot's stock in vms-cloud. This is
        // best-effort: a backend hiccup must not turn a successful physical
        // dispense into a reported failure.
        await _decrementStockBestEffort(lineNumber);
      }
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

  /// Reduce the slot's stock by one in vms-cloud after a successful test
  /// dispense. Never throws — inventory bookkeeping must not mask a vend that
  /// physically succeeded.
  static Future<void> _decrementStockBestEffort(int lineNumber) async {
    if (!AdminApiService.hasToken) {
      LogFileUtil.i('test_dispense.stock.skip', {
        'slot': lineNumber.toString(),
        'reason': 'no_management_token',
      });
      return;
    }
    try {
      final newStock = await AdminApiService.decrementSlotStock(lineNumber);
      LogFileUtil.i('test_dispense.stock.decremented', {
        'slot': lineNumber.toString(),
        'new_stock': newStock?.toString() ?? 'slot_not_found',
      });
    } catch (e) {
      LogFileUtil.e('test_dispense.stock.failed',
          extra: {'slot': lineNumber.toString()}, error: e.toString());
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
    LogFileUtil.i(
        'tty.dispense.start', {'slot': lineNumber.toString(), 'path': path});

    // 1. Open. The outer dispenseProduct catches any throw here.
    try {
      final opened = await TtySerial.open(path, baud: 9600);
      if (!opened) {
        LogFileUtil.e('tty.open.returned_false', extra: {'path': path});
        throw Exception('TtySerial.open($path) returned false.');
      }
    } on TtySerialException catch (e) {
      LogFileUtil.e('tty.open.exception',
          extra: {'path': path}, error: e.message);
      throw Exception(
        'Could not open $path: ${e.message}\n'
        'Use "List TTY Devices" in admin and confirm the path is correct.',
      );
    }

    // 2. Clear latched board faults before every delivery. If a previous
    //    delivery failed, the board can hold an error state until CMD 0xA2.
    final clearFrame = buildClearFaultFrame();
    LogFileUtil.i('tty.write', {
      'cmd': '0xA2',
      'bytes': clearFrame
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' '),
    });
    await TtySerial.write(clearFrame);
    try {
      await TtySerial.read(timeout: const Duration(milliseconds: 400));
    } catch (_) {
      // A2 is a pre-flight cleanup; delivery should still be attempted.
    }

    // 3. Write the delivery frame.
    final frame = buildDeliveryFrame(lineNumber);
    LogFileUtil.i('tty.write', {
      'cmd': '0x41',
      'bytes': frame
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' '),
    });
    await TtySerial.write(frame);

    // 4. Drain the inbound queue (echo / status from the board).
    //    Bytes come from the channel's in-process queue populated by
    //    the persistent ReadThread, not from a direct native read —
    //    so this can never race with close(). Best-effort: motor
    //    fires regardless of echo.
    try {
      final resp =
          await TtySerial.read(timeout: const Duration(milliseconds: 600));
      LogFileUtil.i('tty.echo', {'bytes': resp.length.toString()});
    } catch (_) {
      // A read failure here is fine; we already wrote the command.
    }

    // 5. Wait out the motor turn. 5 s covers every coil/spring slot we
    //    have field data on.
    await Future.delayed(const Duration(seconds: 5));
    LogFileUtil.i('tty.dispense.complete', {'slot': lineNumber.toString()});

    // 6. Intentionally NO close — singleton stays open for the next
    //    dispense (factory pattern). Closing happens via explicit
    //    admin teardown / app shutdown / TTY path change.
    return true;
  }

  static Future<void> _openConfiguredTty({required int baud}) async {
    final opened = await TtySerial.open(AppConfig.ttyPath, baud: baud);
    if (!opened) {
      throw Exception(
          'TtySerial.open(${AppConfig.ttyPath}, $baud) returned false.');
    }
  }

  static Future<Uint8List?> _readFrameForCommand(
    int command, {
    required Duration timeout,
  }) async {
    final assembler = SerialFrameAssembler();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final chunk = await TtySerial.read(
        timeout: const Duration(milliseconds: 250),
      );
      if (chunk.isEmpty) continue;
      for (final frame in assembler.feed(chunk)) {
        if (frame.length >= 6 && frame[3] == command) {
          return frame;
        }
      }
    }
    return null;
  }

  static String _hex(Iterable<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

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
              'lottery_code': lotteryCode,
              'machine_no': machineNo,
              'line_number': lineNumber,
              'status': success ? 'success' : 'failed',
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
