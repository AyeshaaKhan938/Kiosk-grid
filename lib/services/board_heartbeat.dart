import 'dart:async';

import 'app_config.dart';
import 'log_file_util.dart';
import 'vending_machine_service.dart';

/// Periodic Reyeah Control Board heartbeat — mirrors factory.apk's
/// background `onQuerySend` (CMD 0xE1) poll.
///
/// What it does:
///   - every [interval], if no dispense is currently in flight on the
///     VendingMachineService gate, sends a CMD 0xE1 status frame and
///     records the round-trip outcome to LogFileUtil.
///   - skips silently when the app is in Simulate Dispense mode
///     (there's no real hardware to query), or on non-Android.
///
/// What it's for:
///   - detecting "the board died" / "the UART cable came loose" without
///     waiting for a customer to attempt a vend and see no motor turn.
///   - producing a heartbeat trail in the log file the operator can
///     point to when troubleshooting field issues.
///
/// What it deliberately doesn't do:
///   - throw exceptions. Heartbeat failures are logged, never surfaced
///     to the customer UI.
///   - touch the in-flight dispense gate. The single-flight gate in
///     VendingMachineService already serializes everything; heartbeat
///     simply pulses through the same gate so it queues behind any
///     active dispense instead of fighting for the TTY.
class BoardHeartbeat {
  BoardHeartbeat._();
  static final BoardHeartbeat instance = BoardHeartbeat._();

  Timer? _timer;
  bool _running = false;

  /// Start the heartbeat loop. Safe to call multiple times — only the
  /// first call wires up the timer.
  void start({Duration interval = const Duration(seconds: 60)}) {
    if (_running) return;
    _running = true;
    // Delay the first pulse so app startup isn't immediately competing
    // with the initial dispense / boot UI.
    Future<void>.delayed(const Duration(seconds: 20), _pulse);
    _timer = Timer.periodic(interval, (_) => _pulse());
    LogFileUtil.i('heartbeat.start',
        {'interval_sec': interval.inSeconds.toString()});
  }

  /// Stop the heartbeat. The next call to `start()` will reactivate it.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    LogFileUtil.i('heartbeat.stop');
  }

  Future<void> _pulse() async {
    if (AppConfig.simulateDispense) {
      // No hardware to query; nothing useful to log per pulse either.
      return;
    }
    try {
      final ok = await VendingMachineService.queryStatusViaGate();
      LogFileUtil.i(ok ? 'heartbeat.ok' : 'heartbeat.no_reply');
    } catch (e, st) {
      LogFileUtil.e('heartbeat.error', error: e, stack: st);
    }
  }
}

