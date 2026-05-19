import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/admin_api_service.dart';

/// Pantalla de gestión de productos del catálogo.
/// Permite crear nuevos productos y editar los existentes directamente
/// desde el kiosk, sin necesidad de acceder a vms-cloud.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  List<Map<String, dynamic>> _products = [];
  bool    _loading = true;
  String? _error;
  String  _query   = '';
  int     _page    = 1;
  int     _lastPage = 1;
  int     _total   = 0;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1, String? search}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await AdminApiService.getProducts(
        search:  search ?? (_query.isEmpty ? null : _query),
        page:    page,
        perPage: 30,
      );
      final items = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta  = data['meta'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          _products = items;
          _page     = meta['current_page'] as int? ?? 1;
          _lastPage = meta['last_page']    as int? ?? 1;
          _total    = meta['total']        as int? ?? items.length;
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openForm({Map<String, dynamic>? product}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductFormSheet(product: product),
    );
    if (saved == true) _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Product',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Column(children: [
        // ── Search bar ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) {
              _query = v;
              Future.delayed(const Duration(milliseconds: 400), () {
                if (_query == v) _load(page: 1, search: v.isEmpty ? null : v);
              });
            },
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded,
                  color: cs.onSurface.withValues(alpha: 0.5), size: 20),
              hintText: 'Search by name, SKU or brand…',
              hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.35), fontSize: 13),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        _query = '';
                        _load(page: 1);
                      })
                  : null,
            ),
          ),
        ),

        // ── Count ──────────────────────────────────────────────────────
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: Row(children: [
              Text('$_total product${_total == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 12)),
              const Spacer(),
              if (_lastPage > 1)
                Text('Page $_page of $_lastPage',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 12)),
            ]),
          ),

        // ── List ───────────────────────────────────────────────────────
        Expanded(child: _buildBody(cs)),

        // ── Pagination ─────────────────────────────────────────────────
        if (!_loading && _error == null && _lastPage > 1)
          _PaginationBar(
            page: _page, lastPage: _lastPage,
            onPrev: () => _load(page: _page - 1),
            onNext: () => _load(page: _page + 1),
          ),
      ]),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 12)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ]),
      ));
    }
    if (_products.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inventory_2_outlined,
            size: 56, color: cs.onSurface.withValues(alpha: 0.25)),
        const SizedBox(height: 12),
        Text(_query.isEmpty ? 'No products yet' : 'No results for "$_query"',
            style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.45), fontSize: 14)),
        if (_query.isEmpty) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add first product'),
          ),
        ],
      ]));
    }

    return RefreshIndicator(
      onRefresh: () => _load(page: 1),
      color: cs.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount: _products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => _ProductCard(
          product: _products[i],
          onTap: () => _openForm(product: _products[i]),
        ),
      ),
    );
  }
}

// ── Product card ──────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final name     = product['name']     as String? ?? '—';
    final sku      = product['sku']      as String?;
    final brand    = product['brand']    as String?;
    final price    = _parsePrice(product['price']);
    final isActive = product['is_active'] as bool? ?? true;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? cs.primary.withValues(alpha: 0.12)
                : cs.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: isActive
                  ? cs.primary.withValues(alpha: 0.1)
                  : cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.inventory_2_outlined,
                color: isActive ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.3),
                size: 22),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(name,
                    style: TextStyle(
                        color: isActive ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (!isActive)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Inactive',
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                if (sku != null) ...[
                  Text(sku, style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 11)),
                  const SizedBox(width: 8),
                ],
                if (brand != null)
                  Text(brand, style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.35),
                      fontSize: 11)),
              ]),
            ],
          )),
          const SizedBox(width: 10),

          // Price
          if (price > 0)
            Text('\$${price.toStringAsFixed(2)}',
                style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w800, fontSize: 15)),

          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: cs.onSurface.withValues(alpha: 0.3), size: 20),
        ]),
      ),
    );
  }
}

// ── Product form sheet ────────────────────────────────────────────────────────

class _ProductFormSheet extends StatefulWidget {
  /// null = crear nuevo, non-null = editar existente
  final Map<String, dynamic>? product;
  const _ProductFormSheet({this.product});

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  bool _saving   = false;
  bool _isActive = true;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _descCtrl;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl    = TextEditingController(text: p?['name']        as String? ?? '');
    _skuCtrl     = TextEditingController(text: p?['sku']         as String? ?? '');
    _brandCtrl   = TextEditingController(text: p?['brand']       as String? ?? '');
    _barcodeCtrl = TextEditingController(text: p?['barcode']     as String? ?? '');
    _descCtrl    = TextEditingController(text: p?['description'] as String? ?? '');
    final price  = _parsePrice(p?['price']);
    final cost   = _parsePrice(p?['cost']);
    _priceCtrl   = TextEditingController(text: price > 0 ? price.toStringAsFixed(2) : '');
    _costCtrl    = TextEditingController(text: cost  > 0 ? cost.toStringAsFixed(2)  : '');
    _isActive    = p?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _skuCtrl, _brandCtrl, _barcodeCtrl,
                     _priceCtrl, _costCtrl, _descCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final fields = <String, dynamic>{
      'name':      _nameCtrl.text.trim(),
      if (_skuCtrl.text.trim().isNotEmpty)     'sku':     _skuCtrl.text.trim(),
      if (_brandCtrl.text.trim().isNotEmpty)   'brand':   _brandCtrl.text.trim(),
      if (_barcodeCtrl.text.trim().isNotEmpty) 'barcode': _barcodeCtrl.text.trim(),
      if (_descCtrl.text.trim().isNotEmpty)    'description': _descCtrl.text.trim(),
      if (_priceCtrl.text.trim().isNotEmpty)
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
      if (_costCtrl.text.trim().isNotEmpty)
        'cost': double.tryParse(_costCtrl.text.trim()) ?? 0.0,
      'is_active': _isActive,
    };

    try {
      if (_isEditing) {
        await AdminApiService.updateProduct(
            widget.product!['id'] as int, fields);
      } else {
        await AdminApiService.createProduct(fields);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize:     0.6,
      maxChildSize:     0.97,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: sc,
            padding: EdgeInsets.fromLTRB(
                24, 12, 24,
                MediaQuery.of(context).viewInsets.bottom + 32),
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
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      _isEditing ? Icons.edit_rounded : Icons.add_rounded,
                      color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  _isEditing ? 'Edit Product' : 'New Product',
                  style: TextStyle(color: cs.onSurface,
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ]),
              const SizedBox(height: 24),

              // ── Name ────────────────────────────────────────────────
              _label('PRODUCT NAME *'),
              const SizedBox(height: 6),
              _field(
                controller: _nameCtrl,
                hint: 'e.g. Coca-Cola 355ml',
                icon: Icons.label_rounded,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              // ── SKU + Barcode row ────────────────────────────────────
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('SKU'),
                    const SizedBox(height: 6),
                    _field(controller: _skuCtrl,
                        hint: 'e.g. CC-355', icon: Icons.qr_code_rounded),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('BARCODE'),
                    const SizedBox(height: 6),
                    _field(controller: _barcodeCtrl,
                        hint: '012345678901',
                        icon: Icons.barcode_reader,
                        keyboardType: TextInputType.number),
                  ],
                )),
              ]),
              const SizedBox(height: 16),

              // ── Brand ───────────────────────────────────────────────
              _label('BRAND'),
              const SizedBox(height: 6),
              _field(controller: _brandCtrl,
                  hint: 'e.g. Coca-Cola Company',
                  icon: Icons.business_rounded),
              const SizedBox(height: 16),

              // ── Price + Cost row ─────────────────────────────────────
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('SELLING PRICE'),
                    const SizedBox(height: 6),
                    _field(
                      controller: _priceCtrl,
                      hint: '0.00',
                      icon: Icons.sell_rounded,
                      prefix: '\$',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                    ),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('COST'),
                    const SizedBox(height: 6),
                    _field(
                      controller: _costCtrl,
                      hint: '0.00',
                      icon: Icons.receipt_rounded,
                      prefix: '\$',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                    ),
                  ],
                )),
              ]),
              const SizedBox(height: 16),

              // ── Description ──────────────────────────────────────────
              _label('DESCRIPTION'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                style: TextStyle(color: cs.onSurface, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Optional product description…',
                  hintStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.3), fontSize: 13),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 16),

              // ── Active toggle ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.toggle_on_rounded,
                      color: _isActive ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.4),
                      size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Active',
                          style: TextStyle(color: cs.onSurface,
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('Visible in kiosk catalog',
                          style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.45),
                              fontSize: 11)),
                    ],
                  )),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeThumbColor: cs.primary,
                  ),
                ]),
              ),
              const SizedBox(height: 28),

              // ── Save button ──────────────────────────────────────────
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isEditing ? 'Save Changes' : 'Create Product',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: TextStyle(
    color: Theme.of(context).colorScheme.primary,
    fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4,
  ));

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? prefix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: TextStyle(color: cs.onSurface, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.3), fontSize: 13),
        prefixIcon: prefix != null
            ? Padding(
                padding: const EdgeInsets.only(left: 14, right: 4),
                child: Text(prefix,
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 15, fontWeight: FontWeight.w600)),
              )
            : Icon(icon,
                color: cs.onSurface.withValues(alpha: 0.4), size: 18),
        prefixIconConstraints: prefix != null
            ? const BoxConstraints(minWidth: 0, minHeight: 0)
            : null,
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.error, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        errorStyle: TextStyle(color: cs.error, fontSize: 11),
      ),
    );
  }
}

// ── Pagination bar ────────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int page;
  final int lastPage;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _PaginationBar({
    required this.page, required this.lastPage,
    required this.onPrev, required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(
            color: cs.onSurface.withValues(alpha: 0.08))),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          onPressed: page > 1 ? onPrev : null,
          icon: const Icon(Icons.chevron_left_rounded),
          color: cs.primary,
          disabledColor: cs.onSurface.withValues(alpha: 0.2),
        ),
        const SizedBox(width: 8),
        Text('$page / $lastPage',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(width: 8),
        IconButton(
          onPressed: page < lastPage ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
          color: cs.primary,
          disabledColor: cs.onSurface.withValues(alpha: 0.2),
        ),
      ]),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

double _parsePrice(dynamic v) {
  if (v == null) return 0.0;
  if (v is num)  return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}
