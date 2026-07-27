import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/advertisement.dart';
import '../models/machine_slot.dart';
import '../models/product_category.dart';
import '../services/advertisement_service.dart';
import '../services/cart_service.dart';
import '../services/slot_service.dart';
import '../widgets/kiosk_app_header.dart';
import 'admin_config_screen.dart';
import 'cart_screen.dart';
import 'idle_screen.dart';
import 'product_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constantes del carousel
// ─────────────────────────────────────────────────────────────────────────────
const double _kCardSpacing  = 10.0;
const double _kSpeedPxSec   = 48.0;
const double _kSidePad      = 24.0;

enum _ProductSort { nameAsc, priceLow, priceHigh, stockFirst }

enum _StockFilter { all, inStockOnly, availableOnly }

double _sidePad(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w > 900) return 32;
  if (w > 600) return 24;
  return 16;
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductBrowserScreen
// ─────────────────────────────────────────────────────────────────────────────
class ProductBrowserScreen extends StatefulWidget {
  /// Set when the customer completed age verification on this visit.
  final String? ageVerificationSessionId;

  const ProductBrowserScreen({
    super.key,
    this.ageVerificationSessionId,
  });

  @override
  State<ProductBrowserScreen> createState() => _ProductBrowserScreenState();
}

class _ProductBrowserScreenState extends State<ProductBrowserScreen> {

  MachineSlotsResponse? _data;
  bool    _loading = true;
  String? _error;

  List<Advertisement> _topAds = [];
  int    _adIndex = 0;
  Timer? _adTimer;
  late   PageController _adCtrl;

  static const List<_BannerSlide> _demoSlides = [
    _BannerSlide(
      title: 'PREMIUM SNACKS',
      subtitle: 'Over 15 snacks & candies to choose from',
      imageUrl: 'https://picsum.photos/seed/snacks-chips/1280/800',
      color: Color(0xFFFF6B35),
    ),
    _BannerSlide(
      title: 'COLD BEVERAGES',
      subtitle: 'Stay refreshed — sodas, water, energy drinks',
      imageUrl: 'https://picsum.photos/seed/beverages-cold/1280/800',
      color: Color(0xFF0066CC),
    ),
    _BannerSlide(
      title: 'TECH ACCESSORIES',
      subtitle: 'Cables, chargers, earbuds — always in stock',
      imageUrl: 'https://picsum.photos/seed/tech-gadgets/1280/800',
      color: Color(0xFF007ACC),
    ),
    _BannerSlide(
      title: 'HEALTH & WELLNESS',
      subtitle: 'Sanitizer, pain relief and more',
      imageUrl: 'https://picsum.photos/seed/health-wellness/1280/800',
      color: Color(0xFF00AA66),
    ),
  ];
  int    _demoIndex = 0;
  Timer? _demoTimer;
  late   PageController _demoCtrl;

  int       _secretTaps = 0;
  DateTime? _lastTap;

  String _selectedCategory = 'All';
  _ProductSort _sort = _ProductSort.stockFirst;
  _StockFilter _stockFilter = _StockFilter.all;

  static const int _numRows = 3;

  @override
  void initState() {
    super.initState();
    _adCtrl   = PageController();
    _demoCtrl = PageController();
    _loadSlots();
    _loadAds();
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    _demoTimer?.cancel();
    _adCtrl.dispose();
    _demoCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadSlots() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await SlotService.fetchSlots();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().contains('machine_not_found')
            ? 'Machine not configured. Contact your operator.'
            : 'Could not connect to server. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAds() async {
    try {
      final ads = await AdvertisementService.fetchAds();
      if (mounted) {
        final usable = ads.top.where(_isUsableTopAd).toList();
        setState(() => _topAds = usable);
        if (usable.isNotEmpty) _startAdTimer();
      }
    } catch (_) {}
  }

  /// Ignore placeholder/test top banners from cloud admin.
  static bool _isUsableTopAd(Advertisement ad) {
    if (ad.type != AdMediaType.image) return false;
    final url = ad.mediaUrl?.trim() ?? '';
    if (url.isEmpty) return false;
    final title = ad.title.trim().toLowerCase();
    if (title.isEmpty || title == 'test' || title == 'placeholder') {
      return false;
    }
    return true;
  }

  List<String> get _categoryNames {
    final fromApi = _data?.categories ?? const <ProductCategory>[];
    if (fromApi.isNotEmpty) {
      final sorted = [...fromApi]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return ['All', ...sorted.map((c) => c.name)];
    }
    final fromSlots = <String>{};
    for (final s in _data?.slots ?? const <MachineSlot>[]) {
      final c = s.productCategory?.trim();
      if (c != null && c.isNotEmpty) fromSlots.add(c);
    }
    final list = fromSlots.toList()..sort();
    return ['All', ...list];
  }

  List<MachineSlot> get _filteredSlots {
    var list = [...(_data?.slots ?? const <MachineSlot>[])];
    if (_selectedCategory != 'All') {
      list = list
          .where((s) => s.productCategory?.trim() == _selectedCategory)
          .toList();
    }
    switch (_stockFilter) {
      case _StockFilter.inStockOnly:
        list = list.where((s) => !s.isOutOfStock).toList();
      case _StockFilter.availableOnly:
        list = list.where((s) => s.isAvailable && !s.isOutOfStock).toList();
      case _StockFilter.all:
        break;
    }
    switch (_sort) {
      case _ProductSort.nameAsc:
        list.sort((a, b) => a.productName.compareTo(b.productName));
      case _ProductSort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _ProductSort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _ProductSort.stockFirst:
        list.sort((a, b) {
          final aScore = (!a.isAvailable || a.isOutOfStock) ? 1 : 0;
          final bScore = (!b.isAvailable || b.isOutOfStock) ? 1 : 0;
          if (aScore != bScore) return aScore.compareTo(bScore);
          return a.productName.compareTo(b.productName);
        });
    }
    return list;
  }

  void _showSortSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.sort_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Text('Sort products',
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            _sortTile('In stock first', _ProductSort.stockFirst, Icons.check_circle_outline),
            _sortTile('Name A → Z', _ProductSort.nameAsc, Icons.sort_by_alpha),
            _sortTile('Price: low to high', _ProductSort.priceLow, Icons.arrow_upward),
            _sortTile('Price: high to low', _ProductSort.priceHigh, Icons.arrow_downward),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sortTile(String label, _ProductSort value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final selected = _sort == value;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.5)),
      title: Text(label,
          style: TextStyle(
              color: cs.onSurface,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      trailing: selected ? Icon(Icons.check_rounded, color: cs.primary) : null,
      onTap: () {
        setState(() => _sort = value);
        Navigator.pop(context);
      },
    );
  }

  void _showFilterSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Text('Filter products',
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            _filterTile('Show all', _StockFilter.all),
            _filterTile('In stock only', _StockFilter.inStockOnly),
            _filterTile('Available to buy', _StockFilter.availableOnly),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _filterTile(String label, _StockFilter value) {
    final cs = Theme.of(context).colorScheme;
    final selected = _stockFilter == value;
    return ListTile(
      title: Text(label,
          style: TextStyle(
              color: cs.onSurface,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      trailing: selected ? Icon(Icons.check_rounded, color: cs.primary) : null,
      onTap: () {
        setState(() => _stockFilter = value);
        Navigator.pop(context);
      },
    );
  }

  void _showCategorySheet() {
    final cs = Theme.of(context).colorScheme;
    final cats = _categoryNames;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.75,
        builder: (_, scrollCtrl) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.category_outlined, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Text('Shop by category',
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: cats.length,
                  itemBuilder: (_, i) {
                    final cat = cats[i];
                    final selected = _selectedCategory == cat;
                    final count = cat == 'All'
                        ? (_data?.slots.length ?? 0)
                        : (_data?.slots
                                .where((s) => s.productCategory?.trim() == cat)
                                .length ??
                            0);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: selected
                            ? cs.primary.withValues(alpha: 0.15)
                            : cs.surfaceContainerHighest,
                        child: Icon(
                          cat == 'All'
                              ? Icons.apps_rounded
                              : Icons.local_offer_outlined,
                          color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                          size: 18,
                        ),
                      ),
                      title: Text(cat,
                          style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.bold : FontWeight.w500)),
                      subtitle: Text('$count items'),
                      trailing: selected
                          ? Icon(Icons.check_circle_rounded, color: cs.primary)
                          : null,
                      onTap: () {
                        setState(() => _selectedCategory = cat);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _sortLabel {
    switch (_sort) {
      case _ProductSort.nameAsc:
        return 'A → Z';
      case _ProductSort.priceLow:
        return 'Price ↑';
      case _ProductSort.priceHigh:
        return 'Price ↓';
      case _ProductSort.stockFirst:
        return 'In stock';
    }
  }

  String get _filterLabel {
    switch (_stockFilter) {
      case _StockFilter.all:
        return 'All items';
      case _StockFilter.inStockOnly:
        return 'In stock';
      case _StockFilter.availableOnly:
        return 'Available';
    }
  }

  void _startAdTimer() {
    _adTimer?.cancel();
    _adTimer = Timer.periodic(AdvertisementService.defaultSlideDuration, (_) {
      if (!mounted || _topAds.isEmpty) return;
      final next = (_adIndex + 1) % _topAds.length;
      setState(() => _adIndex = next);
      _adCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    });
  }

  void _startDemoTimer() {
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_demoIndex + 1) % _demoSlides.length;
      setState(() => _demoIndex = next);
      if (_demoCtrl.hasClients) {
        _demoCtrl.animateToPage(next,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut);
      }
    });
  }

  // ── Rows ──────────────────────────────────────────────────────────────────

  List<List<MachineSlot>> get _rowSlots {
    final slots = _data?.slots ?? [];
    final rows  = List.generate(_numRows, (_) => <MachineSlot>[]);
    for (int i = 0; i < slots.length; i++) {
      rows[i % _numRows].add(slots[i]);
    }
    return rows;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _onSecretTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inSeconds > 2) _secretTaps = 0;
    _lastTap = now;
    if (++_secretTaps >= 5) { _secretTaps = 0; showAdminPinDialog(context); }
  }

  void _onProductTapped(MachineSlot slot) {
    if (!slot.isAvailable) return;
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => ProductDetailScreen(
        slot: slot,
        ageVerificationSessionId: widget.ageVerificationSessionId,
      ),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 280),
    ));
  }

  void _onAddToCart(MachineSlot slot) {
    if (!slot.isAvailable || slot.isOutOfStock) return;
    CartService.instance.add(slot);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${slot.productName} added to cart'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CartScreen(
          ageVerificationSessionId: widget.ageVerificationSessionId,
        ),
      ),
    );
  }

  void _goBackToIdle() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, animation, __) => const IdleScreen(),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size       = MediaQuery.of(context).size;
    final isPortrait = size.height > size.width;
    final pad        = _sidePad(context);
    final showBanner = _topAds.isNotEmpty;
    final adHeight   = showBanner
        ? (isPortrait ? size.height * 0.14 : size.height * 0.18)
        : 0.0;

    final cs      = Theme.of(context).colorScheme;
    final bg      = Theme.of(context).scaffoldBackgroundColor;
    final primary = cs.primary;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: MobileCartFab(onTap: _openCart),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: Column(
        children: [
          _buildHeader(cs: cs, primary: primary, pad: pad),
          if (showBanner)
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: adHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildBanner(primary: primary),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_topAds.length > 1)
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _topAds.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _adIndex ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _adIndex
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : Colors.white.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          _buildShopToolbar(cs: cs, bg: bg, primary: primary, pad: pad),
          _buildCategoryBar(cs: cs, primary: primary, pad: pad),
          Expanded(child: _buildProductGrid(cs: cs, primary: primary)),
          _buildBackBar(cs: cs, bg: bg, pad: pad),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader({
    required ColorScheme cs,
    required Color primary,
    required double pad,
  }) {
    return KioskAppHeader(
      title: _data?.machineName ?? 'VMFS USA',
      subtitle: (_data?.slots.length ?? 0) > 0
          ? '${_data!.slots.length} products · Tap to shop'
          : 'Browse & buy',
      onLogoTap: _onSecretTap,
      onRefresh: _loadSlots,
      onCart: _openCart,
    );
  }

  Widget _buildShopToolbar({
    required ColorScheme cs,
    required Color bg,
    required Color primary,
    required double pad,
  }) {
    final visible = _filteredSlots.length;
    return Container(
      padding: EdgeInsets.fromLTRB(pad, 10, pad, 6),
      color: bg,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolChip(
              icon: Icons.sort_rounded,
              label: _sortLabel,
              onTap: _showSortSheet,
              primary: primary,
              cs: cs,
            ),
            const SizedBox(width: 8),
            _ToolChip(
              icon: Icons.tune_rounded,
              label: _filterLabel,
              onTap: _showFilterSheet,
              primary: primary,
              cs: cs,
            ),
            const SizedBox(width: 8),
            _ToolChip(
              icon: Icons.menu_rounded,
              label: 'Categories',
              onTap: _showCategorySheet,
              primary: primary,
              cs: cs,
            ),
            const SizedBox(width: 12),
            Text(
              '$visible shown',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBar({
    required ColorScheme cs,
    required Color primary,
    required double pad,
  }) {
    final cats = _categoryNames;
    if (cats.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final selected = _selectedCategory == cat;
          return FilterChip(
            label: Text(cat),
            selected: selected,
            showCheckmark: false,
            labelStyle: TextStyle(
              color: selected ? cs.onPrimary : cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            selectedColor: primary,
            backgroundColor: cs.surfaceContainerHighest,
            side: BorderSide(
              color: selected
                  ? primary
                  : cs.onSurface.withValues(alpha: 0.12),
            ),
            onSelected: (_) => setState(() => _selectedCategory = cat),
          );
        },
      ),
    );
  }

  // ── Banner ────────────────────────────────────────────────────────────────

  Widget _buildBanner({required Color primary}) {
    return PageView.builder(
      controller: _adCtrl,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _topAds.length,
      itemBuilder: (_, i) {
        final ad = _topAds[i];
        return CachedNetworkImage(
          imageUrl: ad.mediaUrl!,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: const Color(0xFF0A1628)),
          errorWidget: (_, __, ___) => Container(color: const Color(0xFF0A1628)),
        );
      },
    );
  }

  // Removed: _adFallback — test/placeholder ads are filtered in _loadAds.

  // ── Product grid ──────────────────────────────────────────────────────────

  Widget _buildProductGrid({required ColorScheme cs, required Color primary}) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: primary, strokeWidth: 2.5));
    }
    if (_error != null) return _buildError(_error!, cs: cs, primary: primary);
    final slots = _filteredSlots;
    if (slots.isEmpty) {
      if ((_data?.slots ?? []).isNotEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_off_outlined,
                  color: cs.onSurface.withValues(alpha: 0.35), size: 40),
              const SizedBox(height: 10),
              Text('No products match your filters.',
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.65),
                      fontSize: 13)),
              TextButton(
                onPressed: () => setState(() {
                  _selectedCategory = 'All';
                  _stockFilter = _StockFilter.all;
                }),
                child: const Text('Clear filters'),
              ),
            ],
          ),
        );
      }
      return _buildEmpty(cs: cs);
    }

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 900 ? 4 : (width > 600 ? 3 : 2);
    final pad = _sidePad(context);

    return RefreshIndicator(
      onRefresh: _loadSlots,
      color: primary,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.72,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: slots.length,
        itemBuilder: (ctx, i) => _GridProductCard(
          slot: slots[i],
          onTap: () => _onProductTapped(slots[i]),
          onAdd: () => _onAddToCart(slots[i]),
        ),
      ),
    );
  }

  // ── All rows (legacy marquee — kept for reference, unused) ────────────────

  Widget _buildAllRows(double cardWidth, {required ColorScheme cs, required Color primary}) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(
          color: primary, strokeWidth: 2.5));
    }
    if (_error != null) return _buildError(_error!, cs: cs, primary: primary);
    final slots = _data?.slots ?? [];
    if (slots.isEmpty) return _buildEmpty(cs: cs);

    const rowSpacing = 8.0;
    final rows = _rowSlots;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: List.generate(_numRows, (r) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top:    r == 0            ? 0 : rowSpacing / 2,
              bottom: r == _numRows - 1 ? 0 : rowSpacing / 2,
            ),
            child: _MarqueeRow(
              key: ValueKey('row_$r'),
              slots:     rows[r],
              forward:   r.isEven,
              cardWidth: cardWidth,
              onTap:     _onProductTapped,
            ),
          ),
        )),
      ),
    );
  }

  // ── Back bar ──────────────────────────────────────────────────────────────

  Widget _buildBackBar({
    required ColorScheme cs,
    required Color bg,
    required double pad,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Go back to advertisements screen',
            button: true,
            child: GestureDetector(
              onTap: _goBackToIdle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.arrow_back_ios_new_rounded,
                      color: cs.onSurface.withValues(alpha: 0.65), size: 12),
                  const SizedBox(width: 5),
                  Text('Back to ads',
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 11)),
                ]),
              ),
            ),
          ),
          const Spacer(),
          Text('VMFS USA © 2026',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildError(String msg, {required ColorScheme cs, required Color primary}) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi_off_rounded, color: cs.onSurface.withValues(alpha: 0.48), size: 40),
      const SizedBox(height: 10),
      Text(msg, textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 13)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _loadSlots,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ),
      ),
    ]),
  );

  Widget _buildEmpty({required ColorScheme cs}) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.inventory_2_outlined, color: cs.onSurface.withValues(alpha: 0.32), size: 40),
      const SizedBox(height: 10),
      Text('No products available right now.',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 13)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _MarqueeRow
//
// Motor: AnimationController(0→1, repeat) + Transform.translate
//   → En web: CSS translateX() → GPU compositor, sin layout cost
//
// Taps: GestureDetector(behavior: opaque) FUERA del Transform captura todos
//   los taps del área del row. _handleTap calcula matemáticamente qué card
//   fue tocada usando el valor actual del AnimationController.
//
//   Por qué: GestureDetector DENTRO de Transform.translate nunca recibe taps
//   porque Flutter hace hit-testing en coordenadas pre-transformadas — el widget
//   "no existe" en la posición sin desplazar. La solución es un único detector
//   externo que conoce el offset actual y deduce el índice de la card.
// ─────────────────────────────────────────────────────────────────────────────
class _MarqueeRow extends StatefulWidget {
  final List<MachineSlot>          slots;
  final bool                       forward;
  final double                     cardWidth;
  final void Function(MachineSlot) onTap;

  const _MarqueeRow({
    super.key,
    required this.slots,
    required this.forward,
    required this.cardWidth,
    required this.onTap,
  });

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;

  // Usa la constante global _kSidePad (90 px)

  double get _cycleWidth =>
      widget.slots.length * (widget.cardWidth + _kCardSpacing);

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    final ms = (_cycleWidth / _kSpeedPxSec * 1000).round().clamp(5000, 120000);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    )..repeat();
  }

  @override
  void didUpdateWidget(_MarqueeRow old) {
    super.didUpdateWidget(old);
    if (old.cardWidth != widget.cardWidth ||
        old.slots.length != widget.slots.length) {
      final ms = (_cycleWidth / _kSpeedPxSec * 1000).round().clamp(5000, 120000);
      _ctrl.duration = Duration(milliseconds: ms);
      if (!_ctrl.isAnimating) _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pause()  { _ctrl.stop(); }
  void _resume() { if (mounted && !_ctrl.isAnimating) _ctrl.repeat(); }

  // ── Cálculo matemático de qué card fue tocada ─────────────────────────────
  //
  // localX : posición X del tap dentro del GestureDetector (incluye _kSidePad)
  //
  // El Row está desplazado `pixelOffset` píxeles a la izquierda.
  // La posición en el Row = (localX - sidePad) + pixelOffset
  // Normalizamos al primer ciclo con módulo para encontrar el índice del slot.
  void _handleTap(double localX) {
    if (_cycleWidth <= 0) return;

    // Quitar padding lateral izquierdo
    final x = localX - _kSidePad;
    if (x < 0) return; // tocó el padding, no una card

    // Cuántos píxeles está desplazado el contenido hacia la izquierda ahora mismo
    final pixelOffset = widget.forward
        ? _ctrl.value * _cycleWidth
        : (1.0 - _ctrl.value) * _cycleWidth;

    // Posición en el espacio del Row (sin transformación)
    final rowX = x + pixelOffset;

    // Normalizar al primer ciclo
    final cycleX = rowX % _cycleWidth;

    // Ancho de una card + su gap
    final step = widget.cardWidth + _kCardSpacing;

    // Índice del slot
    final idx = (cycleX / step).floor();

    // Ignorar si el tap cayó en el gap entre cards
    if ((cycleX % step) > widget.cardWidth) return;

    if (idx < 0 || idx >= widget.slots.length) return;

    final slot = widget.slots[idx];
    if (slot.isAvailable) widget.onTap(slot);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) return const SizedBox();

    // 3× repetición para loop seamless
    final items = [...widget.slots, ...widget.slots, ...widget.slots];

    return GestureDetector(
      // opaque: captura taps en TODA el área del row,
      // independientemente de lo que haya debajo del transform
      behavior: HitTestBehavior.opaque,
      onTapDown:   (_) => _pause(),
      onTapUp:     (d) {
        _handleTap(d.localPosition.dx);
        Future.delayed(const Duration(milliseconds: 600), _resume);
      },
      onTapCancel: () => Future.delayed(
          const Duration(milliseconds: 600), _resume),
      onPanStart:  (_) => _pause(),
      onPanUpdate: (d) {
        if (_cycleWidth <= 0) return;
        // Drag izquierda (dx<0) avanza el row forward; derecha (dx>0) lo retrocede.
        // Para rows backward la dirección se invierte.
        final delta = (widget.forward ? -d.delta.dx : d.delta.dx) / _cycleWidth;
        var v = (_ctrl.value + delta) % 1.0;
        if (v < 0) v += 1.0;
        _ctrl.value = v;
      },
      onPanEnd: (d) {
        // Momentum suave: si el usuario soltó rápido, animamos un poco más
        // antes de reanudar el auto-scroll.
        final vx = d.velocity.pixelsPerSecond.dx;
        if (vx.abs() > 200 && _cycleWidth > 0) {
          final momentum = (widget.forward ? -vx : vx) * 0.18 / _cycleWidth;
          var target = (_ctrl.value + momentum).clamp(0.0, 0.9999);
          _ctrl.animateTo(target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.decelerate)
            .then((_) => Future.delayed(
                const Duration(milliseconds: 400), _resume));
        } else {
          Future.delayed(const Duration(milliseconds: 600), _resume);
        }
      },
      child: Stack(
        children: [
          // ── Padding lateral + marquee ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kSidePad),
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  final offset = widget.forward
                      ? -_ctrl.value * _cycleWidth
                      : -(1.0 - _ctrl.value) * _cycleWidth;

                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 0,
                      maxWidth: double.infinity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: items.map((slot) => Padding(
                          padding:
                              const EdgeInsets.only(right: _kCardSpacing),
                          child: SizedBox(
                            width: widget.cardWidth,
                            child: RepaintBoundary(
                              child: _ProductCard(slot: slot),
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Fade sutil en ambos bordes (indica que hay más contenido) ────
          Positioned(
            left: _kSidePad, top: 0, bottom: 0,
            child: IgnorePointer(
              child: Builder(builder: (ctx) {
                final bg = Theme.of(ctx).scaffoldBackgroundColor;
                return Container(
                  width: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [bg, Colors.transparent],
                    ),
                  ),
                );
              }),
            ),
          ),
          Positioned(
            right: _kSidePad, top: 0, bottom: 0,
            child: IgnorePointer(
              child: Builder(builder: (ctx) {
                final bg = Theme.of(ctx).scaffoldBackgroundColor;
                return Container(
                  width: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [bg, Colors.transparent],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BannerSlide / _DemoBannerSlide
// ─────────────────────────────────────────────────────────────────────────────

class _BannerSlide {
  final String title;
  final String subtitle;
  final String imageUrl;
  final Color  color;
  const _BannerSlide({
    required this.title, required this.subtitle,
    required this.imageUrl, required this.color,
  });
}

class _DemoBannerSlide extends StatelessWidget {
  final _BannerSlide slide;
  const _DemoBannerSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      CachedNetworkImage(
        imageUrl: slide.imageUrl, fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          decoration: BoxDecoration(gradient: LinearGradient(
            colors: [slide.color.withValues(alpha: 0.5), Colors.black])),
        ),
        errorWidget: (_, __, ___) =>
            Container(color: slide.color.withValues(alpha: 0.2)),
      ),
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [slide.color.withValues(alpha: 0.82),
              slide.color.withValues(alpha: 0.28), Colors.transparent],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
      ),
      Positioned(
        left: _kSidePad, bottom: 24,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(slide.title,
              style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.bold, letterSpacing: 1.5,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
          const SizedBox(height: 3),
          Text(slide.subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 6)])),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LotteryCouponButton
// ─────────────────────────────────────────────────────────────────────────────

class _LotteryCouponButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LotteryCouponButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24, spreadRadius: 2),
            BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.50),
                blurRadius: 18),
          ],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('🎟', style: TextStyle(fontSize: 18)),
          SizedBox(width: 8),
          Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LOTTERY COUPON',
                style: TextStyle(color: Colors.black, fontSize: 13,
                    fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            Text('Tap to enter your code',
                style: TextStyle(color: Colors.black54,
                    fontSize: 9, letterSpacing: 0.5)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProductCard — solo visual; los taps los maneja _MarqueeRow._handleTap
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final MachineSlot slot;
  const _ProductCard({required this.slot});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final unavailable = !slot.isAvailable;

    return Semantics(
      label: '${slot.productName}'
          '${slot.productBrand != null ? ', by ${slot.productBrand}' : ''}'
          ', ${slot.isOutOfStock ? "out of stock" : "${slot.currentStock} in stock"}'
          '${!slot.isAvailable ? ", unavailable" : ""}',
      button: slot.isAvailable,
      child: AnimatedOpacity(
      opacity:  unavailable ? 0.35 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.surface,
            border: Border.all(
              color: unavailable
                  ? Colors.transparent
                  : primary,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                    alpha: unavailable ? 0.05 : 0.13),
                blurRadius: 14,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Imagen (ocupa ~62% de la tarjeta) ─────────────────────────
              Expanded(
                flex: 62,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13)),
                  child: Stack(fit: StackFit.expand, children: [
                    _buildImage(cs: cs, primary: primary),
                    if (slot.isOutOfStock)
                      _buildBadge('OUT OF STOCK', Colors.black87),
                    if (slot.isFault)
                      _buildBadge('FAULT', Colors.red.withValues(alpha: 0.8)),
                    // Slot # badge
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.60),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('#${slot.lineNumber}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 9)),
                      ),
                    ),
                  ]),
                ),
              ),

              // ── Info (38% restante) ────────────────────────────────────────
              Expanded(
                flex: 38,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand
                      if (slot.productBrand != null)
                        Text(slot.productBrand!,
                            style: TextStyle(
                              color: primary.withValues(alpha: 0.75),
                              fontSize: 9, fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 1),
                      // Nombre
                      Expanded(
                        child: Text(slot.productName,
                            style: TextStyle(color: cs.onSurface,
                                fontSize: 11, fontWeight: FontWeight.w600,
                                height: 1.2),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      // Stock indicator (prices hidden — kiosk is lottery-only)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('${slot.currentStock} left',
                            style: TextStyle(
                              color: slot.currentStock <= 3
                                  ? Colors.orangeAccent
                                  : cs.onSurface.withValues(alpha: 0.65),
                              fontSize: 10,
                            )),
                      ),
                      const SizedBox(height: 4),
                      _buildStockBar(primary: primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage({required ColorScheme cs, required Color primary}) {
    if (slot.productImage != null && slot.productImage!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: slot.productImage!,
        fit: BoxFit.cover,
        memCacheWidth: 300, memCacheHeight: 400,
        placeholder: (_, __) => Container(color: cs.surfaceContainerHighest),
        errorWidget: (_, __, ___) => _placeholder(cs: cs, primary: primary),
      );
    }
    return _placeholder(cs: cs, primary: primary);
  }

  Widget _placeholder({required ColorScheme cs, required Color primary}) => Container(
    color: cs.surfaceContainerHighest,
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inventory_2_outlined,
          color: primary.withValues(alpha: 0.25), size: 36),
      if (slot.productBrand != null) ...[
        const SizedBox(height: 4),
        Text(slot.productBrand!,
            style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.32), fontSize: 9),
            textAlign: TextAlign.center),
      ],
    ]),
  );

  Widget _buildBadge(String text, Color bg) => Container(
    color: bg,
    child: Center(child: Text(text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 10,
            fontWeight: FontWeight.bold, letterSpacing: 1))),
  );

  Widget _buildStockBar({required Color primary}) {
    final ratio = slot.maxStock > 0
        ? (slot.currentStock / slot.maxStock).clamp(0.0, 1.0)
        : 0.0;
    final color = slot.isOutOfStock
        ? Colors.red.withValues(alpha: 0.6)
        : ratio <= 0.3
            ? Colors.orange.withValues(alpha: 0.8)
            : primary.withValues(alpha: 0.7);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: ratio, minHeight: 3,
        backgroundColor: Colors.white12,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid product card — image, name, price, + Add
// ─────────────────────────────────────────────────────────────────────────────

class _GridProductCard extends StatelessWidget {
  final MachineSlot slot;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _GridProductCard({
    required this.slot,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final soldOut = slot.isOutOfStock || !slot.isAvailable;

    return Material(
      elevation: soldOut ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: soldOut ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (slot.productImage != null &&
                      slot.productImage!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: slot.productImage!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: cs.surfaceContainerHighest),
                      errorWidget: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.inventory_2_outlined,
                            color: primary.withValues(alpha: 0.3), size: 40),
                      ),
                    )
                  else
                    Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.inventory_2_outlined,
                          color: primary.withValues(alpha: 0.3), size: 40),
                    ),
                  if (slot.productCategory != null &&
                      slot.productCategory!.trim().isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          slot.productCategory!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (soldOut)
                    Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: const Text('Sold out',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (slot.productBrand != null &&
                        slot.productBrand!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        slot.productBrand!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          slot.priceFormatted,
                          style: TextStyle(
                            color: primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        if (!soldOut)
                          Material(
                            color: const Color(0xFFFF6B35),
                            borderRadius: BorderRadius.circular(10),
                            elevation: 1,
                            child: InkWell(
                              onTap: onAdd,
                              borderRadius: BorderRadius.circular(10),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add, color: Colors.white, size: 16),
                                    SizedBox(width: 2),
                                    Text('Add',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color primary;
  final ColorScheme cs;

  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: primary),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
