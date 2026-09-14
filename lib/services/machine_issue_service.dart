import '../models/machine_issue_component.dart';
import 'kiosk_cloud_service.dart';
import 'log_file_util.dart';
import 'machine_issue_reporter.dart';

/// Convenience hooks for subsystem fault reporting to VMFS Cloud.
final class MachineIssueService {
  MachineIssueService._();

  static final MachineIssueService instance = MachineIssueService._();

  MachineIssueReporter? get _reporter => KioskCloudService.instance.reporter;

  bool get isEnabled => _reporter != null;

  Future<void> reportDispenseFailure({
    required int slotNumber,
    String? error,
    String? lotteryCode,
  }) async {
    final reporter = _reporter;
    if (reporter == null) return;

    LogFileUtil.i('issue.report.dispense', {
      'slot': slotNumber.toString(),
      if (error != null) 'error': error,
    });

    await reporter.report(
      component: MachineIssueComponent.dispense,
      code: 'dispense_failure',
      title: 'Dispense failure — slot $slotNumber',
      message: error,
      slotNumber: slotNumber,
      metadata: {
        if (lotteryCode != null && lotteryCode.isNotEmpty)
          'lottery_code': lotteryCode,
      },
    );
  }

  Future<void> resolveDispenseFailure({required int slotNumber}) async {
    await _reporter?.resolve(
      component: MachineIssueComponent.dispense,
      code: 'dispense_failure',
      slotNumber: slotNumber,
    );
  }

  Future<void> reportBoardOffline({required String message}) async {
    final reporter = _reporter;
    if (reporter == null) return;

    LogFileUtil.i('issue.report.board_offline', {'message': message});

    await reporter.report(
      component: MachineIssueComponent.connectivity,
      code: 'BOARD_NO_REPLY',
      title: 'Control board not responding',
      message: message,
    );
  }

  Future<void> resolveBoardOffline() async {
    await _reporter?.resolve(
      component: MachineIssueComponent.connectivity,
      code: 'BOARD_NO_REPLY',
    );
  }

  Future<void> reportElevatorFault({required String message}) async {
    await _reporter?.report(
      component: MachineIssueComponent.elevator,
      code: 'ELEV_FAULT',
      message: message,
    );
  }

  Future<void> reportPusherFault({
    required int slotNumber,
    required String message,
  }) async {
    await _reporter?.report(
      component: MachineIssueComponent.pusher,
      code: 'COIL_STUCK',
      slotNumber: slotNumber,
      message: message,
    );
  }

  Future<void> reportPaymentOffline({required String message}) async {
    await _reporter?.report(
      component: MachineIssueComponent.payment,
      code: 'PAYMENT_OFFLINE',
      message: message,
    );
  }

  Future<void> reportDoorFault({required String message}) async {
    await _reporter?.report(
      component: MachineIssueComponent.door,
      code: 'DOOR_FAULT',
      message: message,
    );
  }

  Future<void> resolveDoorFault() async {
    await _reporter?.resolve(
      component: MachineIssueComponent.door,
      code: 'DOOR_FAULT',
    );
  }

  Future<void> flushOfflineQueue() async {
    await _reporter?.flushOfflineQueue();
  }
}
