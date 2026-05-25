import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/admin_api_service.dart';
import '../../widgets/onscreen_keypad.dart';

/// Laravel devuelve price como String ("2.50") o num. Parseamos ambos.
double _parsePrice(dynamic v) {
  if (v == null) return 0.0;
  if (v is num)  return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

class AdminInventoryScreen extends StatefulWidget {
  const AdminInventoryScreen({super.key});

  @override
  State<AdminInventoryScreen> createState() => _AdminInventoryScreenState();
}

class _AdminInventoryScreenState extends State<AdminInventoryScreen> {
  List<Map<String, dynamic>> _slots = [];
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
      final data = await AdminApiService.getAdminSlots();
      final raw  = (data['slots'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _slots = raw; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) return Center(child: CircularProgressIndicator(color: cs.primary));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    return RefreshIndicator(
      onRefresh: _load,
      color: cs.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _slots.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _SlotCard(slot: _slots[i], onUpdated: _load),
      ),
    );
  }
}

// ── Slot card ─────────────────────────────────────────────────────────────────

class _SlotCard extends StatelessWidget {
  final Map<String, dynamic> slot;
  final VoidCallback onUpdated;
  const _SlotCard({required this.slot, required this.onUpdated});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final lineNum    = slot['line_number']   as int;
    final name       = slot['product_name']  as String? ?? 'Empty slot';
    final sku        = slot['product_sku']   as String?;
    final current    = slot['current_stock'] as int?    ?? 0;
    final max        = slot['max_stock']     as int?    ?? 1;
    final price      = _parsePrice(slot['price']);
    final isActive   = slot['is_active']     as bool?   ?? false;
    final isFault    = slot['is_fault']      as bool?   ?? false;
    final isLow      = slot['is_low_stock']  as bool?   ?? false;
    final hasProduct = slot['product_id']    != null;

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    if (isFault) {
      statusColor = Colors.redAccent; statusIcon = Icons.error_rounded;         statusLabel = 'Fault';
    } else if (!isActive) {
      statusColor = cs.onSurface.withValues(alpha: 0.35); statusIcon = Icons.pause_circle_rounded; statusLabel = 'Inactive';
    } else if (!hasProduct) {
      statusColor = Colors.orange; statusIcon = Icons.inbox_rounded;            statusLabel = 'Empty';
    } else if (isLow) {
      statusColor = Colors.orange; statusIcon = Icons.warning_amber_rounded;    statusLabel = 'Low';
    } else {
      statusColor = Colors.green;  statusIcon = Icons.check_circle_rounded;     statusLabel = 'OK';
    }

    final stockFraction = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SlotEditorSheet(slot: slot, onSaved: onUpdated),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFault ? Colors.redAccent.withValues(alpha: 0.5)
                : !hasProduct ? Colors.orange.withValues(alpha: 0.4)
                : isLow ? Colors.orange.withValues(alpha: 0.4)
                : cs.primary.withValues(alpha: 0.12),
          ),
        ),
        child: Row(children: [
          // Badge
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text('#$lineNum',
                style: TextStyle(color: statusColor,
                    fontWeight: FontWeight.bold, fontSize: 14))),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(color: cs.onSurface,
                      fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (sku != null)
                Text(sku, style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.45), fontSize: 11)),
              if (hasProduct)
                Text('\$${price.toStringAsFixed(2)}',
                    style: TextStyle(color: cs.primary,
                        fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stockFraction,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                    color: stockFraction < 0.25 ? Colors.redAccent
                        : stockFraction < 0.5 ? Colors.orange : Colors.green,
                    minHeight: 6,
                  ),
                )),
                const SizedBox(width: 8),
                Text('$current/$max',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ],
          )),
          const SizedBox(width: 10),

          // Status
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(statusIcon, color: statusColor, size: 20),
            const SizedBox(height: 3),
            Text(statusLabel, style: TextStyle(color: statusColor,
                fontSize: 9, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: cs.onSurface.withValues(alpha: 0.3), size: 20),
        ]),
      ),
    );
  }
}

// ── Slot editor sheet ─────────────────────────────────────────────────────────

class _SlotEditorSheet extends StatefulWidget {
  final Map<String, dynamic> slot;
  final VoidCallback onSaved;
  const _SlotEditorSheet({required this.slot, required this.onSaved});

  @override
  State<_SlotEditorSheet> createState() => _SlotEditorSheetState();
}

class _SlotEditorSheetState extends State<_SlotEditorSheet> {
  late int    _stock;
  late int    _maxStock;
  late int    _alarm;
  late bool   _isActive;
  late bool   _isFault;
  late double _price;

  // producto asignado al slot (puede cambiar)
  int?    _productId;
  String? _productName;
  String? _productSku;
  // ignore: unused_field
  String? _productImage;

  bool _saving = false;
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _stock       = widget.slot['current_stock']        as int?    ?? 0;
    _maxStock    = widget.slot['max_stock']             as int?    ?? 10;
    _alarm       = widget.slot['stock_alarm_threshold'] as int?    ?? 3;
    _isActive    = widget.slot['is_active']             as bool?   ?? true;
    _isFault     = widget.slot['is_fault']              as bool?   ?? false;
    _price       = _parsePrice(widget.slot['price']);
    _productId   = widget.slot['product_id']            as int?;
    _productName = widget.slot['product_name']          as String?;
    _productSku  = widget.slot['product_sku']           as String?;
    _productImage = widget.slot['product_image']        as String?;
    _priceCtrl   = TextEditingController(
        text: _price > 0 ? _price.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final priceVal = double.tryParse(_priceCtrl.text.trim()) ?? _price;
      await AdminApiService.updateSlot(widget.slot['id'] as int, {
        if (_productId != null) 'product_id': _productId,
        'price':                priceVal,
        'current_stock':        _stock,
        'max_stock':            _maxStock,
        'stock_alarm_threshold': _alarm,
        'is_active':            _isActive,
        'is_fault':             _isFault,
      });
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickProduct() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProductPickerSheet(),
    );
    if (result != null && mounted) {
      setState(() {
        _productId    = result['id']    as int?;
        _productName  = result['name']  as String?;
        _productSku   = result['sku']   as String?;
        _productImage = result['image'] as String?;
        // Suggest price from product if slot has none
        if (_price == 0) {
          final p = _parsePrice(result['price']);
          if (p > 0) {
            _price = p;
            _priceCtrl.text = p.toStringAsFixed(2);
          }
        }
      });
    }
  }

  void _clearProduct() {
    setState(() {
      _productId    = null;
      _productName  = null;
      _productSku   = null;
      _productImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final bg   = Theme.of(context).scaffoldBackgroundColor;
    final line = widget.slot['line_number'] as int;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(
              24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2)),
            )),

            // Header
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text('#$line',
                    style: TextStyle(color: cs.primary,
                        fontWeight: FontWeight.bold, fontSize: 14))),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Edit Slot #$line',
                    style: TextStyle(color: cs.onSurface,
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Tap fields to modify',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 11)),
              ]),
            ]),
            const SizedBox(height: 24),

            // ── Product assignment ───────────────────────────────────────
            _sectionLabel(context, 'PRODUCT'),
            const SizedBox(height: 8),
            _productId != null
                ? _ProductChip(
                    name:     _productName ?? 'Product #$_productId',
                    sku:      _productSku,
                    onChange: _pickProduct,
                    onClear:  _clearProduct,
                  )
                : OutlinedButton.icon(
                    onPressed: _pickProduct,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Assign product to slot'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
            const SizedBox(height: 20),

            // ── Price ────────────────────────────────────────────────────
            _sectionLabel(context, 'PRICE'),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              readOnly: true,
              showCursor: true,
              enableInteractiveSelection: false,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              style: TextStyle(color: cs.onSurface, fontSize: 15,
                  fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.attach_money_rounded,
                    color: cs.onSurface.withValues(alpha: 0.5), size: 20),
                hintText: '0.00',
                hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.3)),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
              onTap: () => showKeypad(
                context,
                controller: _priceCtrl,
                mode: KeypadMode.numericDecimal,
                title: 'PRICE',
                hint: '0.00',
              ),
            ),
            const SizedBox(height: 20),

            // ── Stock ────────────────────────────────────────────────────
            _sectionLabel(context, 'STOCK'),
            const SizedBox(height: 12),
            _EditorRow(
              label: 'Current stock',
              value: _stock,
              min: 0, max: _maxStock,
              onDec: () => setState(() => _stock--),
              onInc: () => setState(() => _stock++),
            ),
            const SizedBox(height: 12),
            _EditorRow(
              label: 'Max capacity',
              value: _maxStock,
              min: 1, max: 999,
              onDec: () => setState(() {
                _maxStock--;
                if (_stock > _maxStock) _stock = _maxStock;
                if (_alarm  > _maxStock) _alarm  = _maxStock;
              }),
              onInc: () => setState(() => _maxStock++),
            ),
            const SizedBox(height: 12),
            _EditorRow(
              label: 'Low stock alarm at',
              value: _alarm,
              min: 0, max: _maxStock,
              icon: Icons.notifications_active_outlined,
              iconColor: Colors.orange,
              onDec: () => setState(() => _alarm--),
              onInc: () => setState(() => _alarm++),
            ),
            const SizedBox(height: 20),

            // ── Status toggles ───────────────────────────────────────────
            _sectionLabel(context, 'STATUS'),
            const SizedBox(height: 8),
            _SwitchRow(
              label: 'Active',
              subtitle: 'Slot is available for purchase',
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const Divider(height: 1),
            _SwitchRow(
              label: 'Fault',
              subtitle: 'Mark as hardware fault — hides from customers',
              value: _isFault,
              onChanged: (v) => setState(() => _isFault = v),
              dangerColor: true,
            ),
            const SizedBox(height: 28),

            // ── Save ─────────────────────────────────────────────────────
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                  : const Text('Save Changes',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(text, style: TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5,
    ));
  }
}

// ── Product chip (assigned product) ──────────────────────────────────────────

class _ProductChip extends StatelessWidget {
  final String name;
  final String? sku;
  final VoidCallback onChange;
  final VoidCallback onClear;
  const _ProductChip({
    required this.name, this.sku,
    required this.onChange, required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.inventory_2_outlined,
              color: cs.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: TextStyle(color: cs.onSurface,
                fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (sku != null)
              Text(sku!, style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5), fontSize: 11)),
          ],
        )),
        TextButton(
          onPressed: onChange,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text('Change', style: TextStyle(color: cs.primary, fontSize: 12)),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded,
              color: cs.onSurface.withValues(alpha: 0.4), size: 18),
          onPressed: onClear,
          tooltip: 'Remove product',
        ),
      ]),
    );
  }
}

// ── Product picker sheet ──────────────────────────────────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  List<Map<String, dynamic>> _products = [];
  bool   _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch([String? q]) async {
    setState(() => _loading = true);
    try {
      final data = await AdminApiService.getProducts(search: q, perPage: 50);
      final raw  = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _products = raw; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2)),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(children: [
              Text('Select Product',
                  style: TextStyle(color: cs.onSurface,
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              // Search
              TextField(
                controller: _searchCtrl,
                readOnly: true,
                showCursor: true,
                enableInteractiveSelection: false,
                onTap: () => showKeypad(
                  context,
                  controller: _searchCtrl,
                  mode: KeypadMode.alphanumeric,
                  title: 'SEARCH PRODUCTS',
                  hint: 'Name or SKU',
                  onCommitted: (v) => _fetch(v.isEmpty ? null : v),
                ),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded,
                      color: cs.onSurface.withValues(alpha: 0.5), size: 20),
                  hintText: 'Search by name or SKU…',
                  hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.35),
                      fontSize: 13),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            _fetch();
                          },
                        )
                      : null,
                ),
              ),
            ]),
          ),

          const Divider(height: 1),

          // List
          Expanded(child: _loading
              ? Center(child: CircularProgressIndicator(color: cs.primary))
              : _error != null
                  ? Center(child: Text(_error!,
                        style: TextStyle(color: cs.error, fontSize: 13)))
                  : _products.isEmpty
                      ? Center(child: Text('No products found',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))))
                      : ListView.separated(
                          controller: sc,
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          itemCount: _products.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final p    = _products[i];
                            final name = p['name'] as String? ?? '—';
                            final sku  = p['sku']  as String?;
                            final price = _parsePrice(p['price']);
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              leading: Container(
                                width: 42, height: 42,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.inventory_2_outlined,
                                    color: cs.primary, size: 20),
                              ),
                              title: Text(name,
                                  style: TextStyle(color: cs.onSurface,
                                      fontWeight: FontWeight.w600, fontSize: 13),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: sku != null
                                  ? Text(sku, style: TextStyle(
                                        color: cs.onSurface.withValues(alpha: 0.45),
                                        fontSize: 11))
                                  : null,
                              trailing: price > 0
                                  ? Text('\$${price.toStringAsFixed(2)}',
                                      style: TextStyle(color: cs.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13))
                                  : null,
                              onTap: () => Navigator.of(context).pop({
                                'id':    p['id'],
                                'name':  name,
                                'sku':   sku,
                                'price': price,
                                'image': p['image'],
                              }),
                            );
                          },
                        ),
          ),
        ]),
      ),
    );
  }
}

// ── Shared row widgets ────────────────────────────────────────────────────────

class _EditorRow extends StatelessWidget {
  final String   label;
  final int      value;
  final int      min;
  final int      max;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final IconData? icon;
  final Color?    iconColor;

  const _EditorRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onDec,
    required this.onInc,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon!, size: 16, color: iconColor ?? cs.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        Row(children: [
          _StepBtn(Icons.remove_rounded,
              value <= min ? null : onDec),
          const SizedBox(width: 16),
          SizedBox(
            width: 36,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface,
                    fontWeight: FontWeight.bold, fontSize: 20)),
          ),
          const SizedBox(width: 16),
          _StepBtn(Icons.add_rounded,
              value >= max ? null : onInc),
        ]),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? cs.primary.withValues(alpha: 0.12)
              : cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.2),
            size: 18),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dangerColor;
  const _SwitchRow({
    required this.label, required this.subtitle,
    required this.value, required this.onChanged,
    this.dangerColor = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final color = dangerColor ? Colors.redAccent : cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: cs.onSurface,
              fontWeight: FontWeight.w600, fontSize: 13)),
          Text(subtitle, style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5), fontSize: 11)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: color),
      ]),
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
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded, size: 56, color: cs.error),
        const SizedBox(height: 16),
        Text('Failed to load inventory',
            style: TextStyle(color: cs.onSurface,
                fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 12)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ]),
    ));
  }
}
