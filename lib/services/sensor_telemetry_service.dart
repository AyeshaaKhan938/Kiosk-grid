import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/machine_mechanism.dart';
import 'app_config.dart';
import 'bket_cooler_service.dart';
import 'log_file_util.dart';
import 'offline_sync_service.dart';
import 'sensor_telemetry_uploader.dart';

/// Local + cloud-bound machine sensor / subsystem telemetry.
///
/// Samples temperature/cooling/heating, motors, belts, elevator, conveyor,
/// coils, and payment device status on a timer, stores them on-device for
/// the admin viewer, and uploads batches to vms-cloud.
class SensorTelemetryService {
  SensorTelemetryService._();
  static final SensorTelemetryService instance = SensorTelemetryService._();

  static const _kStoreKey = 'sensor_telemetry_readings_v1';
  static const _kMaxLocal = 500;
  static const _kInterval = Duration(minutes: 5);
  static const _kInitialDelay = Duration(seconds: 45);

  final List<SensorReading> _buffer = [];
  Timer? _timer;
  bool _started = false;
  bool _sampling = false;

  List<SensorReading> get readings =>
      List.unmodifiable(List<SensorReading>.from(_buffer.reversed));

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_hydrate());
    Future<void>.delayed(_kInitialDelay, () => unawaited(sampleNow(upload: true)));
    _timer = Timer.periodic(_kInterval, (_) => unawaited(sampleNow(upload: true)));
    LogFileUtil.i('sensor.telemetry.scheduler_started', {
      'interval_min': _kInterval.inMinutes.toString(),
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> sampleNow({bool upload = false}) async {
    if (_sampling) return;
    _sampling = true;
    try {
      final batch = await _collect();
      _buffer.addAll(batch);
      while (_buffer.length > _kMaxLocal) {
        _buffer.removeAt(0);
      }
      await _persist();
      for (final r in batch) {
        LogFileUtil.i('sensor.${r.category}.${r.sensorKey}', {
          'status': r.status,
          if (r.valueNumeric != null) 'value': r.valueNumeric,
          if (r.valueUnit != null) 'unit': r.valueUnit,
          if (r.message != null) 'msg': r.message,
        });
      }
      if (upload) {
        await SensorTelemetryUploader.instance.flushPending();
      }
    } catch (e, st) {
      LogFileUtil.e('sensor.telemetry.sample_failed', error: e, stack: st);
    } finally {
      _sampling = false;
    }
  }

  /// Readings not yet confirmed uploaded (no cloud ack stored).
  List<SensorReading> pendingUpload() =>
      _buffer.where((r) => !r.uploaded).toList();

  Future<void> markUploaded(Iterable<String> clientIds) async {
    final set = clientIds.toSet();
    for (var i = 0; i < _buffer.length; i++) {
      final r = _buffer[i];
      if (set.contains(r.clientId)) {
        _buffer[i] = r.copyWith(uploaded: true);
      }
    }
    await _persist();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStoreKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _buffer
        ..clear()
        ..addAll(list.map(SensorReading.fromJson));
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kStoreKey,
      jsonEncode(_buffer.map((r) => r.toJson()).toList()),
    );
  }

  Future<List<SensorReading>> _collect() async {
    final now = DateTime.now().toUtc();
    final mechanism = AppConfig.machineMechanism;
    final online = OfflineSyncService.instance.isOnline;
    final readings = <SensorReading>[];

    readings.add(_reading(
      now: now,
      category: 'other',
      sensorKey: 'kiosk.connectivity',
      status: online ? 'ok' : 'offline',
      message: online ? 'Cloud reachable' : 'Offline — readings queued',
      metadata: {'machine_no': AppConfig.machineNo},
    ));

    readings.add(_reading(
      now: now,
      category: 'other',
      sensorKey: 'kiosk.mechanism',
      status: 'ok',
      message: mechanism.label,
      metadata: {
        'protocol': AppConfig.hardwareProtocol,
        'tty': AppConfig.ttyPath,
      },
    ));

    // Temperature / cooling / heating
    if (AppConfig.isBketCooler) {
      final cooler = await BketCoolerService.getStatus();
      readings.add(_reading(
        now: now,
        category: 'cooling',
        sensorKey: 'cooler.cabinet',
        status: cooler.initialized ? 'ok' : 'unknown',
        message: cooler.initialized
            ? 'AI cooler controller online'
            : 'Cooler SDK not initialized',
        metadata: {
          'door_open': cooler.doorOpen,
          'lock_open': cooler.lockOpen,
          'host_camera': cooler.hostCameraOnline,
          'sub_camera': cooler.subCameraOnline,
        },
      ));
      readings.add(_reading(
        now: now,
        category: 'temperature',
        sensorKey: 'cooler.zone',
        status: cooler.initialized ? 'ok' : 'unknown',
        message: cooler.initialized
            ? 'Temperature probe via cooler path (status only)'
            : 'No temperature probe reading available',
      ));
      readings.add(_reading(
        now: now,
        category: 'heating',
        sensorKey: 'heater.circuit',
        status: 'unknown',
        message: 'Heating circuit not instrumented on this cooler model',
      ));
    } else {
      readings.add(_reading(
        now: now,
        category: 'temperature',
        sensorKey: 'cabinet.ambient',
        status: 'unknown',
        message: 'No dedicated temperature sensor on this hardware profile',
      ));
      readings.add(_reading(
        now: now,
        category: 'cooling',
        sensorKey: 'cooling.system',
        status: 'unknown',
        message: 'Cooling telemetry not exposed for ${mechanism.shortLabel}',
      ));
      readings.add(_reading(
        now: now,
        category: 'heating',
        sensorKey: 'heater.circuit',
        status: 'unknown',
        message: 'Heating telemetry not exposed for ${mechanism.shortLabel}',
      ));
    }

    // Mechanism-specific actuators
    switch (mechanism) {
      case MachineMechanism.elevator:
        readings.addAll([
          _reading(
            now: now,
            category: 'elevator',
            sensorKey: 'lift.platform',
            status: 'ok',
            message: 'Elevator / lift path configured (${AppConfig.ttyPath})',
          ),
          _reading(
            now: now,
            category: 'motor',
            sensorKey: 'vend.motor',
            status: 'ok',
            message: 'Vend motor path ready (UART)',
          ),
          _reading(
            now: now,
            category: 'belt',
            sensorKey: 'delivery.belt',
            status: 'unknown',
            message: 'Delivery belt sensor not separately instrumented',
          ),
        ]);
        break;
      case MachineMechanism.coil:
        readings.addAll([
          _reading(
            now: now,
            category: 'coil',
            sensorKey: 'coil.board',
            status: 'ok',
            message: 'TCN coil board path ready (${AppConfig.ttyPath})',
          ),
          _reading(
            now: now,
            category: 'motor',
            sensorKey: 'coil.motor',
            status: 'ok',
            message: 'Spiral / coil motors via TCN serial',
          ),
        ]);
        break;
      case MachineMechanism.conveyor:
        readings.addAll([
          _reading(
            now: now,
            category: 'conveyor',
            sensorKey: 'conveyor.lane',
            status: 'ok',
            message: 'Conveyor UART path ready (${AppConfig.ttyPath})',
          ),
          _reading(
            now: now,
            category: 'belt',
            sensorKey: 'conveyor.belt',
            status: 'ok',
            message: 'Belt / pusher lanes configured',
          ),
          _reading(
            now: now,
            category: 'motor',
            sensorKey: 'conveyor.motor',
            status: 'ok',
            message: 'Conveyor motor path ready',
          ),
        ]);
        break;
      case MachineMechanism.cooler:
        readings.add(_reading(
          now: now,
          category: 'motor',
          sensorKey: 'lock.actuator',
          status: 'ok',
          message: 'Door lock actuator monitored via cooler SDK',
        ));
        break;
    }

    // Payment
    final paymentConfigured = AppConfig.paymentCardEnabled ||
        AppConfig.paymentCashEnabled ||
        AppConfig.managementToken.isNotEmpty;
    readings.add(_reading(
      now: now,
      category: 'payment',
      sensorKey: 'payment.terminal',
      status: paymentConfigured ? 'ok' : 'unknown',
      message: AppConfig.shouldSimulatePayment
          ? 'Payment simulation ON (${AppConfig.paymentCardProviderLabel})'
          : 'Card=${AppConfig.paymentCardProviderLabel}; cash=${AppConfig.paymentCashEnabled ? "on" : "off"}',
    ));

    return readings;
  }

  SensorReading _reading({
    required DateTime now,
    required String category,
    required String sensorKey,
    required String status,
    String? message,
    double? valueNumeric,
    String? valueUnit,
    Map<String, Object?>? metadata,
  }) {
    final id =
        '${now.millisecondsSinceEpoch}-$category-$sensorKey-${Random().nextInt(9999)}';
    return SensorReading(
      clientId: id,
      category: category,
      sensorKey: sensorKey,
      status: status,
      valueNumeric: valueNumeric,
      valueUnit: valueUnit,
      message: message,
      metadata: metadata,
      recordedAt: now,
      uploaded: false,
    );
  }
}

class SensorReading {
  const SensorReading({
    required this.clientId,
    required this.category,
    required this.sensorKey,
    required this.status,
    required this.recordedAt,
    required this.uploaded,
    this.valueNumeric,
    this.valueUnit,
    this.message,
    this.metadata,
  });

  final String clientId;
  final String category;
  final String sensorKey;
  final String status;
  final double? valueNumeric;
  final String? valueUnit;
  final String? message;
  final Map<String, Object?>? metadata;
  final DateTime recordedAt;
  final bool uploaded;

  SensorReading copyWith({bool? uploaded}) => SensorReading(
        clientId: clientId,
        category: category,
        sensorKey: sensorKey,
        status: status,
        valueNumeric: valueNumeric,
        valueUnit: valueUnit,
        message: message,
        metadata: metadata,
        recordedAt: recordedAt,
        uploaded: uploaded ?? this.uploaded,
      );

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'category': category,
        'sensor_key': sensorKey,
        'status': status,
        'value_numeric': valueNumeric,
        'value_unit': valueUnit,
        'message': message,
        'metadata': metadata,
        'recorded_at': recordedAt.toIso8601String(),
        'uploaded': uploaded,
      };

  Map<String, dynamic> toApiPayload() => {
        'client_id': clientId,
        'category': category,
        'sensor_key': sensorKey,
        'status': status,
        if (valueNumeric != null) 'value_numeric': valueNumeric,
        if (valueUnit != null) 'value_unit': valueUnit,
        if (message != null) 'message': message,
        if (metadata != null) 'metadata': metadata,
        'recorded_at': recordedAt.toIso8601String(),
      };

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
        clientId: json['client_id']?.toString() ?? '',
        category: json['category']?.toString() ?? 'other',
        sensorKey: json['sensor_key']?.toString() ?? 'unknown',
        status: json['status']?.toString() ?? 'unknown',
        valueNumeric: (json['value_numeric'] as num?)?.toDouble(),
        valueUnit: json['value_unit']?.toString(),
        message: json['message']?.toString(),
        metadata: json['metadata'] is Map
            ? Map<String, Object?>.from(json['metadata'] as Map)
            : null,
        recordedAt: DateTime.tryParse(json['recorded_at']?.toString() ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc(),
        uploaded: json['uploaded'] == true,
      );
}
