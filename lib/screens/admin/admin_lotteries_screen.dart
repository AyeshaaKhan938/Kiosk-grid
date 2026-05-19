import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';

class AdminLotteriesScreen extends StatefulWidget {
  const AdminLotteriesScreen({super.key});

  @override
  State<AdminLotteriesScreen> createState() => _AdminLotteriesScreenState();
}

class _AdminLotteriesScreenState extends State<AdminLotteriesScreen> {
  List<Map<String, dynamic>> _lotteries = [];
  bool   _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await AdminApiService.getLotteries();
      final raw  = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _lotteries = raw; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) return Center(child: CircularProgressIndicator(color: cs.primary));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
    if (_lotteries.isEmpty) return _EmptyView();

    return RefreshIndicator(
      onRefresh: _load,
      color: cs.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _lotteries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _LotteryCard(lottery: _lotteries[i]),
      ),
    );
  }
}

class _LotteryCard extends StatelessWidget {
  final Map<String, dynamic> lottery;
  const _LotteryCard({required this.lottery});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final isActive = lottery['is_active'] as bool? ?? false;
    final name     = lottery['name']      as String? ?? '—';
    final product  = lottery['product']   as Map<String, dynamic>?;
    final prizes   = (lottery['prizes']   as List? ?? []).cast<Map<String, dynamic>>();
    final total    = lottery['codes_count']        as int? ?? 0;
    final redeemed = total - (lottery['unredeemed_codes_count'] as int? ?? 0);
    final pct      = total > 0 ? redeemed / total : 0.0;

    String validRange = '';
    final from  = lottery['valid_from']  as String?;
    final until = lottery['valid_until'] as String?;
    if (from != null && until != null) {
      final f = DateTime.tryParse(from);
      final u = DateTime.tryParse(until);
      if (f != null && u != null) {
        validRange = '${f.month}/${f.day}/${f.year} – ${u.month}/${u.day}/${u.year}';
      }
    }

    return InkWell(
      onTap: () => _showDetail(context, lottery),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? Colors.green.withValues(alpha: 0.4)
                : cs.onSurface.withValues(alpha: 0.1),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(color: cs.onSurface,
                        fontWeight: FontWeight.bold, fontSize: 14)),
                if (product != null) ...[
                  const SizedBox(height: 2),
                  Text(product['name'] as String? ?? '',
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55),
                          fontSize: 12)),
                ],
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.green.withValues(alpha: 0.15)
                    : cs.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: isActive ? Colors.green : cs.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ]),

          if (validRange.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(validRange,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45),
                    fontSize: 11)),
          ],

          // Code redemption progress
          if (total > 0) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                  color: cs.primary,
                  minHeight: 6,
                ),
              )),
              const SizedBox(width: 10),
              Text('$redeemed / $total redeemed',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55),
                      fontSize: 11)),
            ]),
          ],

          // Prize chips
          if (prizes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: prizes.map((p) {
              final tier   = p['tier_code']    as String? ?? '';
              final amount = p['prize_amount'] as String? ?? '0';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('$tier \$$amount',
                    style: TextStyle(color: cs.primary,
                        fontSize: 10, fontWeight: FontWeight.w600)),
              );
            }).toList()),
          ],
        ]),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> lottery) {
    final cs   = Theme.of(context).colorScheme;
    final bg   = Theme.of(context).scaffoldBackgroundColor;
    final name = lottery['name'] as String? ?? '—';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.8,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              Center(child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              Text(name, style: TextStyle(color: cs.onSurface,
                  fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              _DetailRow('Token', lottery['public_draw_token'] as String? ?? '—',
                  mono: true),
              _DetailRow('Quantity', '${lottery['quantity'] ?? '—'}'),
              _DetailRow('Generation', lottery['generation_rule'] as String? ?? '—'),
              const SizedBox(height: 16),
              Text('Prizes', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55),
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              ...(lottery['prizes'] as List? ?? [])
                  .cast<Map<String, dynamic>>()
                  .map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.only(right: 8, top: 2),
                        decoration: BoxDecoration(
                          color: cs.primary, shape: BoxShape.circle),
                      ),
                      Expanded(child: Text(
                        '${p['tier_code']} — ${p['name']} — \$${p['prize_amount']} (weight: ${p['weight']})',
                        style: TextStyle(color: cs.onSurface, fontSize: 12),
                      )),
                    ]),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _DetailRow(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55), fontSize: 12)),
          ),
          Expanded(child: Text(value,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
              ))),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.confirmation_num_rounded,
          size: 56, color: cs.onSurface.withValues(alpha: 0.25)),
      const SizedBox(height: 16),
      Text('No lottery campaigns',
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
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 12)),
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
