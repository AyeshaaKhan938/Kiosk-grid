import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'log_file_util.dart';
import 'sensor_telemetry_service.dart';

/// Pushes pending [SensorReading]s to vms-cloud.
class SensorTelemetryUploader {
  SensorTelemetryUploader._();
  static final SensorTelemetryUploader instance = SensorTelemetryUploader._();

  bool _flushing = false;

  Future<int> flushPending() async {
    if (_flushing) return 0;
    if (!AppConfig.autoUploadLogs) return 0;
    if (AppConfig.deviceToken.isEmpty || AppConfig.apiBaseUrl.isEmpty) {
      return 0;
    }

    final pending = SensorTelemetryService.instance.pendingUpload();
    if (pending.isEmpty) return 0;

    _flushing = true;
    try {
      final api = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$api/kiosk/sensor-logs');
      var uploaded = 0;

      // Chunk to stay under API max 200 readings.
      for (var i = 0; i < pending.length; i += 100) {
        final chunk = pending.skip(i).take(100).toList();
        final response = await http
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer ${AppConfig.deviceToken}',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'readings': chunk.map((r) => r.toApiPayload()).toList(),
              }),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await SensorTelemetryService.instance
              .markUploaded(chunk.map((r) => r.clientId));
          uploaded += chunk.length;
          LogFileUtil.i('sensor.telemetry.uploaded', {
            'count': chunk.length.toString(),
            'http': response.statusCode.toString(),
          });
        } else {
          LogFileUtil.w('sensor.telemetry.upload_failed', {
            'http': response.statusCode.toString(),
            'body': response.body.length > 180
                ? '${response.body.substring(0, 180)}…'
                : response.body,
          });
          break;
        }
      }

      return uploaded;
    } catch (e, st) {
      LogFileUtil.e('sensor.telemetry.upload_exception', error: e, stack: st);
      return 0;
    } finally {
      _flushing = false;
    }
  }
}
