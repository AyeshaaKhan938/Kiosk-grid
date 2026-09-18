import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';
import '../../services/app_config.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_page_scaffold.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminApiService.getDashboard();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.accent),
      );
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    if (_data?['offline'] == true) {
      final pending = _data?['pending_sync'] as int? ?? 0;
      return RefreshIndicator(
        onRefresh: _load,
        color: AdminColors.accent,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _OfflineDashboardCard(pendingSync: pending),
            const SizedBox(height: 16),
            const Text(
              'Sales stats and order history need cloud connection. '
              'Inventory, products, and ads can still be managed locally.',
              style: TextStyle(
                color: AdminColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final machine = _data!['machine'] as Map<String, dynamic>;
    final today = _data!['today'] as Map<String, dynamic>;
    final inventory = _data!['inventory'] as Map<String, dynamic>;

    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.accent,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _MachineHeader(machine: machine),
          const SizedBox(height: 20),
          const AdminSectionLabel("Today's sales"),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Completed',
                value: '${today['orders_completed']}',
                icon: Icons.check_circle_rounded,
                color: AdminColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Revenue',
                value: '\$${today['revenue']}',
                icon: Icons.attach_money_rounded,
                color: AdminColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Failed',
                value: '${today['orders_failed']}',
                icon: Icons.cancel_rounded,
                color: AdminColors.danger,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          const AdminSectionLabel('Inventory status'),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Total slots',
                value: '${inventory['total_slots']}',
                icon: Icons.grid_view_rounded,
                color: AdminColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Low stock',
                value: '${inventory['low_stock_count']}',
                icon: Icons.warning_amber_rounded,
                color: AdminColors.warning,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _StatCard(
                label: 'Faulted',
                value: '${inventory['fault_count']}',
                icon: Icons.error_rounded,
                color: AdminColors.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Empty',
                value: '${inventory['empty_count']}',
                icon: Icons.inbox_rounded,
                color: AdminColors.textMuted,
              ),
            ),
          ]),
          const SizedBox(height: 28),
          Text(
            'Machine: ${AppConfig.machineNo}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdminColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MachineHeader extends StatelessWidget {
  final Map<String, dynamic> machine;
  const _MachineHeader({required this.machine});

  @override
  Widget build(BuildContext context) {
    final enabled = machine['is_enabled'] as bool? ?? false;

    return AdminSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AdminColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.smart_screen_rounded,
            color: AdminColors.accent,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                machine['machine_name'] ?? '—',
                style: const TextStyle(
                  color: AdminColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                machine['detailed_address'] ?? '',
                style: const TextStyle(
                  color: AdminColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: enabled
                ? AdminColors.success.withValues(alpha: 0.12)
                : AdminColors.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            enabled ? 'Online' : 'Offline',
            style: TextStyle(
              color: enabled ? AdminColors.success : AdminColors.danger,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AdminSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: AdminColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AdminColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: AdminSurfaceCard(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AdminColors.danger),
            const SizedBox(height: 16),
            const Text(
              'Failed to load',
              style: TextStyle(
                color: AdminColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OfflineDashboardCard extends StatelessWidget {
  const _OfflineDashboardCard({required this.pendingSync});
  final int pendingSync;

  @override
  Widget build(BuildContext context) {
    return AdminSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: AdminColors.accent),
              SizedBox(width: 12),
              Text(
                'Offline mode',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AdminColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pendingSync > 0
                ? '$pendingSync local change(s) will sync when internet returns.'
                : 'Managing catalog from local storage on this device.',
            style: const TextStyle(
              color: AdminColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Machine: ${AppConfig.machineNo}',
            style: const TextStyle(
              color: AdminColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
