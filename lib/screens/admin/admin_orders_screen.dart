import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic> _meta = {};
  bool   _loading = true;
  String? _error;

  String? _statusFilter;           // null | 'completed' | 'failed'
  String? _dateFilter;             // null | 'YYYY-MM-DD' (today)
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) _page = 1;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await AdminApiService.getOrders(
        page:   _page,
        status: _statusFilter,
        date:   _dateFilter,
      );
      final raw  = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = data['meta'] as Map<String, dynamic>? ?? {};
      if (mounted) setState(() {
        _orders = raw;
        _meta   = meta;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String get _todayDate {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(children: [
      // Filter bar
      Container(
        color: cs.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          // Date toggle
          _FilterChip(
            label: 'Today',
            active: _dateFilter != null,
            onTap: () {
              setState(() => _dateFilter = _dateFilter == null ? _todayDate : null);
              _load();
            },
          ),
          const SizedBox(width: 8),
          // Status filters
          _FilterChip(
            label: 'Completed',
            active: _statusFilter == 'completed',
            color: Colors.green,
            onTap: () {
              setState(() => _statusFilter =
                  _statusFilter == 'completed' ? null : 'completed');
              _load();
            },
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Failed',
            active: _statusFilter == 'failed',
            color: Colors.redAccent,
            onTap: () {
              setState(() => _statusFilter =
                  _statusFilter == 'failed' ? null : 'failed');
              _load();
            },
          ),
          const Spacer(),
          if (_meta['total'] != null)
            Text('${_meta['total']} total',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 11)),
        ]),
      ),

      // Body
      Expanded(child: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _orders.isEmpty
                  ? _EmptyView()
                  : _OrderList(
                      orders: _orders,
                      meta:   _meta,
                      onRefresh: _load,
                      onNextPage: () {
                        _page++;
                        _load(reset: false);
                      },
                      onPrevPage: () {
                        if (_page > 1) { _page--; _load(reset: false); }
                      },
                    )),
    ]);
  }
}

class _OrderList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final Map<String, dynamic> meta;
  final Future<void> Function() onRefresh;
  final VoidCallback onNextPage;
  final VoidCallback onPrevPage;
  const _OrderList({
    required this.orders,
    required this.meta,
    required this.onRefresh,
    required this.onNextPage,
    required this.onPrevPage,
  });

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final currentPage = meta['current_page'] as int? ?? 1;
    final lastPage    = meta['last_page']    as int? ?? 1;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: cs.primary,
      child: Column(children: [
        Expanded(child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _OrderCard(order: orders[i]),
        )),

        // Pagination
        if (lastPage > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: cs.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: currentPage > 1 ? onPrevPage : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('Page $currentPage of $lastPage',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600, fontSize: 13)),
                IconButton(
                  onPressed: currentPage < lastPage ? onNextPage : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
      ]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final status  = order['status'] as String? ?? '';
    final isOk    = status == 'completed';
    final color   = isOk ? Colors.green : Colors.redAccent;

    String timeLabel = '';
    final raw = order['created_at'] as String?;
    if (raw != null) {
      final dt  = DateTime.tryParse(raw)?.toLocal();
      if (dt != null) {
        timeLabel =
            '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        // Status dot
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),

        // Details
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order['product_name'] as String? ?? '—',
                style: TextStyle(color: cs.onSurface,
                    fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(children: [
              Text(order['prize_name'] as String? ?? '—',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 11)),
              const SizedBox(width: 8),
              Text('Slot #${order['line_number'] ?? '?'}',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 11)),
            ]),
          ],
        )),

        // Amount + time
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('\$${order['prize_amount'] ?? '0.00'}',
              style: TextStyle(color: cs.primary,
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          Text(timeLabel,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45),
                  fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? accent : cs.onSurface.withValues(alpha: 0.2),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? accent : cs.onSurface.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.receipt_long_rounded,
          size: 56, color: cs.onSurface.withValues(alpha: 0.25)),
      const SizedBox(height: 16),
      Text('No orders found',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 15)),
    ]));
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded, size: 48, color: cs.error),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 12)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ]),
    ));
  }
}
