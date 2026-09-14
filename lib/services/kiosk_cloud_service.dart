import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'log_file_util.dart';
import 'machine_issue_reporter.dart';

/// Cloud device lifecycle: activation, heartbeat, issue queue flush.
final class KioskCloudService {
  KioskCloudService._();

  static final KioskCloudService instance = KioskCloudService._();

  Timer? _heartbeatTimer;
  MachineIssueReporter? _reporter;

  MachineIssueReporter? get reporter => _reporter;

  bool get isActivated => AppConfig.hasDeviceToken;

  void refreshReporter() {
    _reporter = AppConfig.hasDeviceToken
        ? MachineIssueReporter(
            baseUrl: AppConfig.cloudWebOrigin,
            deviceToken: AppConfig.deviceToken,
          )
        : null;
  }

  /// Start periodic cloud heartbeat + issue queue flush.
  void start({Duration interval = const Duration(minutes: 5)}) {
    refreshReporter();
    if (!AppConfig.hasDeviceToken) {
      LogFileUtil.i('cloud.lifecycle.skip', {'reason': 'no_device_token'});
      return;
    }

    _heartbeatTimer?.cancel();
    Future<void>.delayed(const Duration(seconds: 30), () async {
      await heartbeat();
      await _reporter?.flushOfflineQueue();
    });
    _heartbeatTimer = Timer.periodic(interval, (_) => heartbeat());
    LogFileUtil.i('cloud.lifecycle.start', {
      'interval_min': interval.inMinutes.toString(),
    });
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// POST /api/v1/kiosk/activate — stores device token on success.
  Future<String?> activate({required String activationCode}) async {
    final hardwareId = await AppConfig.ensureHardwareId();
    final url = Uri.parse('${AppConfig.apiBaseUrl}/kiosk/activate');

    try {
      final response = await http
          .post(
            url,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'activation_code': activationCode.trim(),
              'hardware_id': hardwareId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final token = body['device_token']?.toString() ?? '';
        if (token.isEmpty) {
          return 'Activation succeeded but no device token was returned.';
        }

        await AppConfig.setDeviceToken(token);
        final machineNo = body['machine_number']?.toString();
        if (machineNo != null && machineNo.isNotEmpty) {
          await AppConfig.setMachineNo(machineNo);
        }

        refreshReporter();
        unawaited(heartbeat());
        LogFileUtil.i('cloud.activate.ok', {
          if (machineNo != null) 'machine_no': machineNo,
        });

        return null;
      }

      final body = _tryDecode(response.body);
      return body?['message']?.toString() ??
          'Activation failed (${response.statusCode}).';
    } catch (e) {
      return 'Activation failed: $e';
    }
  }

  /// POST /api/v1/kiosk/heartbeat
  Future<void> heartbeat() async {
    if (!AppConfig.hasDeviceToken) return;

    final hardwareId = await AppConfig.ensureHardwareId();
    final url = Uri.parse('${AppConfig.apiBaseUrl}/kiosk/heartbeat');

    try {
      final response = await http
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${AppConfig.deviceToken}',
            },
            body: jsonEncode({'hardware_id': hardwareId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _reporter?.flushOfflineQueue();
        LogFileUtil.i('cloud.heartbeat.ok');
        return;
      }

      LogFileUtil.i('cloud.heartbeat.fail', {
        'status': response.statusCode.toString(),
      });
    } catch (e) {
      LogFileUtil.e('cloud.heartbeat.error', error: e);
    }
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
