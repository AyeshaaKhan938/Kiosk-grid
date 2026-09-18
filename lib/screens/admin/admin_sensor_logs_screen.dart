import 'package:flutter/material.dart';

import '../../services/sensor_telemetry_service.dart';
import '../../services/sensor_telemetry_uploader.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_page_scaffold.dart';

/// On-machine viewer for temperature / motors / elevator / coil / payment logs.
class AdminSensorLogsScreen extends StatefulWidget {
  const AdminSensorLogsScreen({super.key});

  @override
  State<AdminSensorLogsScreen> createState() => _AdminSensorLogsScreenState();
}

class _AdminSensorLogsScreenState extends State<AdminSensorLogsScreen> {
  bool _busy = false;
  String? _filter;

  static const _categories = [
    'temperature',
    'cooling',
    'heating',
    'motor',
    'belt',
    'elevator',
    'conveyor',
    'coil',
    'payment',
    'other',
  ];

  Future<void> _refresh({bool upload = false}) async {
    setState(() => _busy = true);
    await SensorTelemetryService.instance.sampleNow(upload: upload);
    if (upload) {
      await SensorTelemetryUploader.instance.flushPending();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = SensorTelemetryService.instance.readings;
    final rows = _filter == null
        ? all
        : all.where((r) => r.category == _filter).toList();
    final pending = SensorTelemetryService.instance.pendingUpload().length;

    return AdminPageScaffold(
      title: 'Sensor logs',
      subtitle: pending > 0 ? '$pending waiting to upload' : 'Synced with cloud',
      leading: AdminPageScaffold.backLeading(context),
      padding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Sample now',
          onPressed: _busy ? null : () => _refresh(),
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Upload to cloud',
          onPressed: _busy ? null : () => _refresh(upload: true),
          icon: const Icon(Icons.cloud_upload_outlined),
        ),
      ],
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                ..._categories.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(c),
                      selected: _filter == c,
                      onSelected: (_) => setState(() => _filter = c),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(minHeight: 2, color: AdminColors.accent),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No sensor readings yet. Tap refresh to sample '
                        'temperature, cooling, motors, belts, elevator, '
                        'conveyor, coils, and payment status.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AdminColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ReadingTile(reading: rows[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({required this.reading});

  final SensorReading reading;

  Color get _statusColor {
    switch (reading.status) {
      case 'ok':
        return AdminColors.success;
      case 'warn':
        return AdminColors.warning;
      case 'fault':
      case 'offline':
        return AdminColors.danger;
      default:
        return AdminColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = reading.valueNumeric != null
        ? '${reading.valueNumeric}${reading.valueUnit != null ? ' ${reading.valueUnit}' : ''}'
        : null;

    return AdminSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AdminColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  reading.category,
                  style: const TextStyle(
                    color: AdminColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reading.sensorKey,
                  style: const TextStyle(
                    color: AdminColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                reading.status.toUpperCase(),
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (value != null) ...[
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: AdminColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (reading.message != null) ...[
            const SizedBox(height: 6),
            Text(
              reading.message!,
              style: const TextStyle(
                color: AdminColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                reading.recordedAt.toLocal().toString().split('.').first,
                style: const TextStyle(
                  color: AdminColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Icon(
                reading.uploaded
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                size: 16,
                color: reading.uploaded
                    ? AdminColors.success
                    : AdminColors.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
