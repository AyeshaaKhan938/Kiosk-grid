import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';
import '../../services/app_config.dart';

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
    setState(() { _loading = true; _error = null; });
    try {
      final data = await AdminApiService.getDashboard();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    if (_data?['offline'] == true) {
      final pending = _data?['pending_sync'] as int? ?? 0;
      return RefreshIndicator(
        onRefresh: _load,
        color: cs.primary,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _OfflineDashboardCard(pendingSync: pending),
            const SizedBox(height: 16),
            Text(
              'Sales stats and order history need cloud connection. '
              'Inventory, products, and ads can still be managed locally.',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.65),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final machine   = _data!['machine']   as Map<String, dynamic>;
    final today     = _data!['today']     as Map<String, dynamic>;
    final inventory = _data!['inventory'] as Map<String, dynamic>;

    return RefreshIndicator(
      onRefresh: _load,
      color: cs.primary,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Machine info header
          _MachineHeader(machine: machine),
          const SizedBox(height: 20),

          // Today's sales
          _SectionLabel('Today\'s Sales'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _StatCard(
              label: 'Completed',
              value: '${today['orders_completed']}',
              icon: Icons.check_circle_rounded,
              color: Colors.green,
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(
              label: 'Revenue',
              value: '\$${today['revenue']}',
              icon: Icons.attach_money_rounded,
              color: cs.primary,
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(
              label: 'Failed',
              value: '${today['orders_failed']}',
              icon: Icons.cancel_rounded,
              color: Colors.redAccent,
            )),
          ]),
          const SizedBox(height: 20),

          // Inventory status
          _SectionLabel('Inventory Status'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _StatCard(
              label: 'Total Slots',
              value: '${inventory['total_slots']}',
              icon: Icons.grid_view_rounded,
              color: cs.onSurface,
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(
              label: 'Low Stock',
              value: '${inventory['low_stock_count']}',
              icon: Icons.warning_amber_rounded,
              color: Colors.orange,
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _StatCard(
              label: 'Faulted',
              value: '${inventory['fault_count']}',
              icon: Icons.error_rounded,
              color: Colors.redAccent,
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(
              label: 'Empty',
              value: '${inventory['empty_count']}',
              icon: Icons.inbox_rounded,
              color: cs.onSurface.withValues(alpha: 0.4),
            )),
          ]),
          const SizedBox(height: 32),
          Text(
            'Machine: ${AppConfig.machineNo}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _MachineHeader extends StatelessWidget {
  final Map<String, dynamic> machine;
  const _MachineHeader({required this.machine});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final bg  = Theme.of(context).scaffoldBackgroundColor;
    final hc  = Theme.of(context).brightness == Brightness.dark;
    final enabled = machine['is_enabled'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.smart_screen_rounded, color: cs.primary, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(machine['machine_name'] ?? '—',
                style: TextStyle(color: cs.onSurface,
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(machine['detailed_address'] ?? '',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12)),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: enabled
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            enabled ? 'Online' : 'Offline',
            style: TextStyle(
              color: enabled ? Colors.green : Colors.redAccent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(text,
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.55),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ));
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
              )),
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: cs.error),
          const SizedBox(height: 16),
          Text('Failed to load', style: TextStyle(color: cs.onSurface,
              fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ]),
      ),
    );
  }
}

class _OfflineDashboardCard extends StatelessWidget {
  const _OfflineDashboardCard({required this.pendingSync});
  final int pendingSync;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: cs.primary),
                const SizedBox(width: 12),
                Text(
                  'Offline mode',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              pendingSync > 0
                  ? '$pendingSync local change(s) will sync when internet returns.'
                  : 'Managing catalog from local storage on this device.',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Machine: ${AppConfig.machineNo}',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
