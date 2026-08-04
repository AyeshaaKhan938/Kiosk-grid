import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/machine_slot.dart';
import '../services/cart_service.dart';
import '../services/purchase_service.dart';
import '../utils/kiosk_page_transitions.dart';
import '../widgets/kiosk_app_header.dart';
import '../widgets/kiosk_interactive.dart';
import 'cart_screen.dart';
import 'purchase_result_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final MachineSlot slot;
  final String? ageVerificationSessionId;

  const ProductDetailScreen({
    super.key,
    required this.slot,
    this.ageVerificationSessionId,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  String _errorMsg = '';
  int _galleryIndex = 0;
  bool _addedFlash = false;

  late PageController _galleryCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _cartPulseCtrl;
  late Animation<double> _cartPulseAnim;

  @override
  void initState() {
    super.initState();
    _galleryCtrl = PageController();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _cartPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _cartPulseAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(
      parent: _cartPulseCtrl,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _galleryCtrl.dispose();
    _fadeCtrl.dispose();
    _cartPulseCtrl.dispose();
    super.dispose();
  }

  MachineSlot get slot => widget.slot;

  void _addToCart() {
    if (!slot.isAvailable || slot.isOutOfStock) {
      setState(() => _errorMsg = 'This product is out of stock.');
      return;
    }
    CartService.instance.add(slot);
    HapticFeedback.lightImpact();
    _cartPulseCtrl.forward(from: 0);
    setState(() {
      _errorMsg = '';
      _addedFlash = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _addedFlash = false);
    });
  }

  Future<void> _buyNow() async {
    if (_isLoading) return;
    if (!slot.isAvailable || slot.isOutOfStock) {
      setState(() => _errorMsg = 'This product is out of stock.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = '';
    });

    try {
      final result = await PurchaseService.checkoutItem(
        slot,
        ageVerificationSessionId: widget.ageVerificationSessionId,
      );
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        kioskSlideRoute(
          builder: (_) => PurchaseResultScreen(purchases: [result]),
        ),
      );
    } on PurchaseException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Purchase failed. Check your connection.';
        });
      }
    }
  }

  void _openCart() {
    context.pushKioskScreen(CartScreen(
      ageVerificationSessionId: widget.ageVerificationSessionId,
    ));
  }

  Color _categoryColor(String? cat, Color fallback) {
    if (cat == null) return fallback;
    const palette = [
      Color(0xFF007ACC),
      Color(0xFF00897B),
      Color(0xFFE65100),
      Color(0xFF6A1B9A),
      Color(0xFF283593),
      Color(0xFF2E7D32),
      Color(0xFFC62828),
      Color(0xFF4E342E),
    ];
    return palette[cat.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final images = slot.allImages;
    final imgH = size.height * 0.32;
    final pad = KioskAppHeader.sidePad(context);

    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final primary = cs.primary;
    final soldOut = slot.isOutOfStock || !slot.isAvailable;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: MobileCartFab(onTap: _openCart),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KioskAppHeader(
              title: slot.productName,
              subtitle: slot.productCategory ?? slot.priceFormatted,
              onBack: () => Navigator.pop(context),
              onCart: _openCart,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroImage(images, imgH, cs: cs, primary: primary),
                    Padding(
                      padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
                      child: _buildInfoContent(
                        cs: cs,
                        bg: bg,
                        primary: primary,
                        soldOut: soldOut,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildBottomBar(cs: cs, primary: primary, soldOut: soldOut, pad: pad),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroImage(
    List<String> images,
    double height, {
    required ColorScheme cs,
    required Color primary,
  }) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          images.isEmpty
              ? _buildImagePlaceholder(cs: cs, primary: primary)
              : PageView.builder(
                  controller: _galleryCtrl,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _galleryIndex = i),
                  itemBuilder: (_, i) => CachedNetworkImage(
                    imageUrl: images[i],
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: cs.surfaceContainerHighest),
                    errorWidget: (_, __, ___) =>
                        _buildImagePlaceholder(cs: cs, primary: primary),
                  ),
                ),
          if (images.length > 1)
            Positioned(
              top: 12,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_galleryIndex + 1} / ${images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (images.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _galleryIndex ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _galleryIndex
                          ? primary
                          : Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder({
    required ColorScheme cs,
    required Color primary,
  }) =>
      Container(
        color: cs.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                color: primary.withValues(alpha: 0.35), size: 64),
            const SizedBox(height: 8),
            Text(slot.productName,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.48), fontSize: 14)),
          ],
        ),
      );

  Widget _buildInfoContent({
    required ColorScheme cs,
    required Color bg,
    required Color primary,
    required bool soldOut,
  }) {
    final catColor = _categoryColor(slot.productCategory, primary);
    final stockRatio = slot.maxStock > 0
        ? (slot.currentStock / slot.maxStock).clamp(0.0, 1.0)
        : 0.0;
    final stockColor = slot.isOutOfStock
        ? Colors.red
        : stockRatio <= 0.3
            ? Colors.orange
            : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (slot.productCategory != null)
              _Chip(
                label: slot.productCategory!,
                color: catColor,
                icon: Icons.category_outlined,
              ),
            if (slot.productBrand != null && slot.productBrand!.isNotEmpty)
              _Chip(
                label: slot.productBrand!,
                color: primary,
                icon: Icons.verified_outlined,
              ),
            _Chip(
              label: 'Slot #${slot.lineNumber}',
              color: cs.onSurface.withValues(alpha: 0.48),
              icon: Icons.point_of_sale_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              slot.priceFormatted,
              style: TextStyle(
                color: primary,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(width: 12),
            if (soldOut)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Sold out',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              )
            else
              Text(
                '${slot.currentStock} in stock',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: stockRatio,
            minHeight: 6,
            backgroundColor: cs.onSurface.withValues(alpha: 0.07),
            valueColor: AlwaysStoppedAnimation<Color>(stockColor),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: stockColor, size: 14),
            const SizedBox(width: 6),
            Text(
              slot.isOutOfStock
                  ? 'Out of stock'
                  : '${slot.currentStock} of ${slot.maxStock} available',
              style: TextStyle(
                color: stockColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (slot.productDescription != null &&
            slot.productDescription!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'DESCRIPTION',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.48),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            slot.productDescription!,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.72),
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ],
        const SizedBox(height: 20),
        _buildDetailsGrid(slot, cs: cs, primary: primary),
        if (_errorMsg.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_errorMsg,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomBar({
    required ColorScheme cs,
    required Color primary,
    required bool soldOut,
    required double pad,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(pad, 10, pad, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.12))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ScaleTransition(
                scale: _cartPulseAnim,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _addedFlash
                          ? const Color(0xFF2E7D32)
                          : primary.withValues(alpha: 0.45),
                      width: _addedFlash ? 2 : 1.5,
                    ),
                    color: _addedFlash
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.08)
                        : Colors.transparent,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: soldOut || _isLoading ? null : _addToCart,
                      child: SizedBox(
                        height: 52,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _addedFlash
                              ? const Row(
                                  key: ValueKey('added'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        color: Color(0xFF2E7D32), size: 22),
                                    SizedBox(width: 8),
                                    Text('Added to cart!',
                                        style: TextStyle(
                                          color: Color(0xFF2E7D32),
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        )),
                                  ],
                                )
                              : Row(
                                  key: const ValueKey('add'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_shopping_cart_outlined,
                                        color: primary, size: 20),
                                    const SizedBox(width: 8),
                                    Text('Add to Cart',
                                        style: TextStyle(
                                          color: primary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        )),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: KioskElevatedButton(
                  onPressed:
                      _isLoading || soldOut ? null : _buyNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        cs.onSurface.withValues(alpha: 0.12),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: soldOut ? 0 : 3,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Buy Now',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsGrid(MachineSlot slot,
      {required ColorScheme cs, required Color primary}) {
    final items = <_DetailItem>[];

    if (slot.productCategory != null) {
      items.add(_DetailItem(
          Icons.category_outlined, 'Category', slot.productCategory!));
    }
    if (slot.productBrand != null && slot.productBrand!.isNotEmpty) {
      items.add(
          _DetailItem(Icons.verified_outlined, 'Brand', slot.productBrand!));
    }
    if (slot.productSku != null && slot.productSku!.isNotEmpty) {
      items.add(_DetailItem(Icons.qr_code_rounded, 'SKU', slot.productSku!));
    }
    if (slot.productWeight != null) {
      items.add(_DetailItem(Icons.scale_outlined, 'Weight',
          '${slot.productWeight} ${slot.productWeightUnit ?? 'g'}'));
    }
    items.add(_DetailItem(
        Icons.point_of_sale_outlined, 'Slot', '#${slot.lineNumber}'));
    if (slot.productId != null) {
      items.add(
          _DetailItem(Icons.tag_rounded, 'Product ID', '${slot.productId}'));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRODUCT DETAILS',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.48),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map((item) => _DetailCard(item: item, cs: cs, primary: primary))
              .toList(),
        ),
      ],
    );
  }
}

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;
  const _DetailItem(this.icon, this.label, this.value);
}

class _DetailCard extends StatelessWidget {
  final _DetailItem item;
  final ColorScheme cs;
  final Color primary;
  const _DetailCard(
      {required this.item, required this.cs, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 15, color: primary),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.label.toUpperCase(),
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.48),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(item.value,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Chip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
