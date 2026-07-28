import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cooler_session.dart';
import 'api_service.dart';
import 'app_config.dart';
import 'bket_cooler_service.dart';
import 'log_file_util.dart';

/// Headless AI cooler flow: poll POS-paid sessions → unlock door → upload
/// videos → poll order until vms-cloud finishes review + billing.
enum CoolerFlowPhase {
  standby,
  sessionActive,
  uploading,
  processing,
  done,
  error,
}

class CoolerOrchestratorService extends ChangeNotifier {
  CoolerOrchestratorService._();

  static final CoolerOrchestratorService instance =
      CoolerOrchestratorService._();

  static const _pollInterval = Duration(seconds: 3);
  static const _orderPollInterval = Duration(seconds: 5);
  static const _doneDisplay = Duration(seconds: 6);
  static const _errorDisplay = Duration(seconds: 12);

  CoolerFlowPhase _phase = CoolerFlowPhase.standby;
  String _statusLine = 'Pay at the register to open the cooler.';
  String? _errorDetail;
  String? _activeOrderId;
  bool _running = false;
  bool _handling = false;
  Timer? _resetTimer;

  CoolerFlowPhase get phase => _phase;
  String get statusLine => _statusLine;
  String? get errorDetail => _errorDetail;
  String? get activeOrderId => _activeOrderId;
  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    LogFileUtil.i('cooler.orchestrator.start');

    if (!kIsWeb && AppConfig.isBketCooler) {
      try {
        await BketCoolerService.initialize();
      } catch (e, st) {
        LogFileUtil.e('cooler.init.failed', error: e, stack: st);
      }
    }

    notifyListeners();
    unawaited(_pollLoop());
  }

  void stop() {
    _running = false;
    _resetTimer?.cancel();
    LogFileUtil.i('cooler.orchestrator.stop');
  }

  Future<void> _pollLoop() async {
    while (_running) {
      if (!_handling && _phase == CoolerFlowPhase.standby) {
        await _checkForPendingSession();
      }
      await Future<void>.delayed(_pollInterval);
    }
  }

  Future<void> _checkForPendingSession() async {
    try {
      final pending = await ApiService.fetchPendingCoolerSession();
      if (pending == null || !_running) return;
      if (!pending.paymentVerified) {
        LogFileUtil.w('cooler.pending.unverified', {
          'orderId': pending.orderId,
        });
        return;
      }
      await _handleSession(pending);
    } catch (e, st) {
      LogFileUtil.e('cooler.poll.failed', error: e, stack: st);
    }
  }

  Future<void> _handleSession(PendingCoolerSession pending) async {
    if (_handling) return;
    _handling = true;
    _resetTimer?.cancel();
    _activeOrderId = pending.orderId;
    _errorDetail = null;

    try {
      LogFileUtil.i('cooler.session.claimed', {
        'orderId': pending.orderId,
        'sessionId': pending.sessionId,
      });

      try {
        await ApiService.acknowledgeCoolerSession(
          orderId: pending.orderId,
          sessionId: pending.sessionId,
        );
      } catch (e) {
        LogFileUtil.w('cooler.ack.failed', {'error': e.toString()});
      }

      _setPhase(
        CoolerFlowPhase.sessionActive,
        'Door unlocking — open the cooler, take your items, then close the door.',
      );

      final hardware = await BketCoolerService.startShoppingSession(
        sessionId: pending.sessionId,
        timeoutSec: AppConfig.bketDoorTimeoutSec,
      );

      if (!hardware.success) {
        final err = hardware.errorMessage ?? 'Cooler session did not complete.';
        await _reportFailure(
          orderId: pending.orderId,
          sessionId: pending.sessionId,
          error: err,
        );
        _showError(err);
        return;
      }

      _setPhase(CoolerFlowPhase.uploading, 'Uploading session video…');

      final hostPath = hardware.hostVideoPath;
      final subPath = hardware.subVideoPath;
      if (hostPath == null || subPath == null) {
        const err = 'Session videos were not recorded.';
        await _reportFailure(
          orderId: pending.orderId,
          sessionId: pending.sessionId,
          error: err,
        );
        _showError(err);
        return;
      }

      try {
        await ApiService.uploadCoolerSession(
          orderId: pending.orderId,
          sessionId: pending.sessionId,
          hostVideoPath: hostPath,
          subVideoPath: subPath,
        );
      } catch (e) {
        await _reportFailure(
          orderId: pending.orderId,
          sessionId: pending.sessionId,
          error: e.toString(),
        );
        _showError('Upload failed. Staff has been notified.');
        return;
      }

      _setPhase(
        CoolerFlowPhase.processing,
        'Processing your purchase — please wait…',
      );

      final finalStatus = await _pollOrderUntilTerminal(pending.orderId);
      if (finalStatus?.isSuccess == true) {
        final amount = finalStatus!.finalAmount;
        final msg = amount != null
            ? 'Thank you! Charged \$${amount.toStringAsFixed(2)}.'
            : 'Thank you! Your purchase is complete.';
        _setPhase(CoolerFlowPhase.done, msg);
        _scheduleReturnToStandby(_doneDisplay);
      } else {
        final msg = finalStatus?.message ??
            'We could not complete billing. Please see staff.';
        _showError(msg);
      }
    } catch (e, st) {
      LogFileUtil.e('cooler.session.unexpected', error: e, stack: st);
      await _reportFailure(
        orderId: pending.orderId,
        sessionId: pending.sessionId,
        error: e.toString(),
      );
      _showError('Something went wrong. Please see staff.');
    }
  }

  Future<CoolerOrderStatus?> _pollOrderUntilTerminal(String orderId) async {
    while (_running) {
      try {
        final status = await ApiService.fetchOrderStatus(orderId);
        if (status.isTerminal) return status;
      } catch (e, st) {
        LogFileUtil.e('cooler.order.poll.failed', error: e, stack: st);
      }
      await Future<void>.delayed(_orderPollInterval);
    }
    return null;
  }

  Future<void> _reportFailure({
    required String orderId,
    required String sessionId,
    required String error,
  }) async {
    LogFileUtil.e('cooler.session.failed', error: error, stack: null);
    try {
      await ApiService.reportCoolerSessionFailure(
        orderId: orderId,
        sessionId: sessionId,
        error: error,
      );
    } catch (_) {}
  }

  void _showError(String message) {
    _errorDetail = message;
    _setPhase(CoolerFlowPhase.error, message);
    _scheduleReturnToStandby(_errorDisplay);
  }

  void _scheduleReturnToStandby(Duration delay) {
    _resetTimer?.cancel();
    _resetTimer = Timer(delay, () {
      if (!_running) return;
      _activeOrderId = null;
      _errorDetail = null;
      _setPhase(
        CoolerFlowPhase.standby,
        'Pay at the register to open the cooler.',
      );
      _handling = false;
    });
  }

  void _setPhase(CoolerFlowPhase phase, String line) {
    _phase = phase;
    _statusLine = line;
    notifyListeners();
    LogFileUtil.i('cooler.phase', {'phase': phase.name, 'line': line});
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
