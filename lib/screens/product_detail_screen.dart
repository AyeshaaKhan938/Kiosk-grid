import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/machine_slot.dart';
import '../services/cart_service.dart';
import '../services/purchase_service.dart';
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
    with SingleTickerProviderStateMixin {

  bool   _isLoading = false;
  String _errorMsg  = '';
  int    _galleryIndex = 0;
  late   PageController _galleryCtrl;
  late   AnimationController _fadeCtrl;
  late   Animation<double>   _fadeAnim;

  // _blue is replaced by cs.primary from build context

  @override
  void initState() {
    super.initState();
    _galleryCtrl = PageController();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _galleryCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Cart / buy ────────────────────────────────────────────────────────────

  void _addToCart() {
    if (!widget.slot.isAvailable || widget.slot.isOutOfStock) {
      setState(() => _errorMsg = 'This product is out of stock.');
      return;
    }
    CartService.instance.add(widget.slot);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.slot.productName} added to cart'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _buyNow() async {
    if (_isLoading) return;
    if (!widget.slot.isAvailable || widget.slot.isOutOfStock) {
      setState(() => _errorMsg = 'This product is out of stock.');
      return;
    }

    setState(() { _isLoading = true; _errorMsg = ''; });

    try {
      final result = await PurchaseService.checkoutItem(
        widget.slot,
        ageVerificationSessionId: widget.ageVerificationSessionId,
      );
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseResultScreen(purchases: [result]),
        ),
      );
    } on PurchaseException catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorMsg = e.message; });
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CartScreen(
          ageVerificationSessionId: widget.ageVerificationSessionId,
        ),
      ),
    );
  }

  // ── Category color ────────────────────────────────────────────────────────

  Color _categoryColor(String? cat, Color fallback) {
    if (cat == null) return fallback;
    const palette = [
      Color(0xFF007ACC), Color(0xFF00897B), Color(0xFFE65100),
      Color(0xFF6A1B9A), Color(0xFF283593), Color(0xFF2E7D32),
      Color(0xFFC62828), Color(0xFF4E342E),
    ];
    return palette[cat.hashCode.abs() % palette.length];
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size    = MediaQuery.of(context).size;
    final images  = widget.slot.allImages;
    final imgH    = size.height * 0.44;

    final cs      = Theme.of(context).colorScheme;
    final bg      = Theme.of(context).scaffoldBackgroundColor;
    final primary = cs.primary;

    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // ── Contenido scrollable ──────────────────────────────────────
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Hero image ──────────────────────────────────────────
                  _buildHeroImage(images, imgH, size, cs: cs, primary: primary),
                  // ── Info ────────────────────────────────────────────────
                  _buildInfoSheet(cs: cs, bg: bg, primary: primary),
                ],
              ),
            ),

            // ── Back button (flotante sobre la imagen) ───────────────────
            Positioned(
              top: 16, left: 24,
              child: SafeArea(
                child: Semantics(
                  label: 'Go back to product list',
                  button: true,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: cs.onSurface, size: 18),
                    ),
                  ),
                ),
              ),
            ),

            // ── Indicador de imagen (X / N) ──────────────────────────────
            if (images.length > 1)
              Positioned(
                top: 20, right: 24,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_galleryIndex + 1} / ${images.length}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Hero image panel ──────────────────────────────────────────────────────

  Widget _buildHeroImage(List<String> images, double height, Size size,
      {required ColorScheme cs, required Color primary}) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Galería
          images.isEmpty
              ? _buildImagePlaceholder(cs: cs, primary: primary)
              : PageView.builder(
                  controller: _galleryCtrl,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _galleryIndex = i),
                  itemBuilder: (_, i) => Semantics(
                    label: '${widget.slot.productName} product image ${i + 1} of ${images.length}',
                    child: CachedNetworkImage(
                      imageUrl: images[i],
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: cs.surfaceContainerHighest),
                      errorWidget: (_, __, ___) => _buildImagePlaceholder(cs: cs, primary: primary),
                    ),
                  ),
                ),

          // Gradiente inferior → funde con el panel de fondo
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, cs.surface],
                ),
              ),
            ),
          ),

          // Dots de galería
          if (images.length > 1)
            Positioned(
              bottom: 12, left: 0, right: 0,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width:  i == _galleryIndex ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _galleryIndex
                          ? primary : Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder({required ColorScheme cs, required Color primary}) => Container(
    color: cs.surfaceContainerHighest,
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inventory_2_outlined,
          color: primary.withValues(alpha: 0.35), size: 72),
      const SizedBox(height: 12),
      Text(widget.slot.productName,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.48), fontSize: 14)),
    ]),
  );

  // ── Info sheet ────────────────────────────────────────────────────────────

  Widget _buildInfoSheet({required ColorScheme cs, required Color bg, required Color primary}) {
    final slot = widget.slot;
    final catColor = _categoryColor(slot.productCategory, primary);
    final stockRatio = slot.maxStock > 0
        ? (slot.currentStock / slot.maxStock).clamp(0.0, 1.0) : 0.0;
    final stockColor = slot.isOutOfStock
        ? Colors.red
        : stockRatio <= 0.3 ? Colors.orange : Colors.green;

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Chips: categoría + brand ─────────────────────────────────
          Wrap(
            spacing: 8, runSpacing: 6,
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
          const SizedBox(height: 14),

          // ── Nombre del producto ──────────────────────────────────────
          Text(
            slot.productName,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),

          // ── Lottery call-out (replaces price — this kiosk is lottery-only) ──
          Semantics(
            label: 'Win this product with a lottery code',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary.withValues(alpha: 0.08), primary.withValues(alpha: 0.03)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(Icons.confirmation_num_outlined,
                      color: primary, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Win this with your lottery code',
                      style: TextStyle(
                        color: primary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Stock bar ────────────────────────────────────────────────
          Semantics(
            label: slot.isOutOfStock
                ? 'Out of stock'
                : '${slot.currentStock} of ${slot.maxStock} units in stock',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: stockColor, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      slot.isOutOfStock
                          ? 'Out of stock'
                          : '${slot.currentStock} of ${slot.maxStock} in stock',
                      style: TextStyle(
                        color: stockColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stockRatio,
                    minHeight: 6,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation<Color>(stockColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Price ────────────────────────────────────────────────────
          Row(
            children: [
              Text(
                slot.priceFormatted,
                style: TextStyle(
                  color: primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 12),
              if (slot.isOutOfStock)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              else if (slot.currentStock > 0)
                Text('${slot.currentStock} in stock',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.45),
                        fontSize: 13)),
            ],
          ),
          const SizedBox(height: 18),

          // ── Divider ──────────────────────────────────────────────────
          Divider(color: cs.onSurface.withValues(alpha: 0.07), height: 1),
          const SizedBox(height: 16),

          // ── Descripción ──────────────────────────────────────────────
          if (slot.productDescription != null &&
              slot.productDescription!.isNotEmpty) ...[
            Text(
              'DESCRIPTION',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.48),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              slot.productDescription!,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.65),
                fontSize: 14,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ── Detalles adicionales ─────────────────────────────────────
          _buildDetailsGrid(slot, cs: cs, primary: primary),
          const SizedBox(height: 24),

          // ── Error ────────────────────────────────────────────────────
          if (_errorMsg.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_errorMsg,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // ── Botones CTA ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _addToCart,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_shopping_cart_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Add to Cart',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ||
                            !slot.isAvailable ||
                            slot.isOutOfStock
                        ? null
                        : _buyNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                      shadowColor: primary.withValues(alpha: 0.4),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: cs.onPrimary, strokeWidth: 2))
                        : const Text('Buy',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: _openCart,
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('View cart'),
            ),
          ),

          const SizedBox(height: 12),
          Center(
            child: Text('VMFS USA © 2026',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.32), fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ── Details grid (ficha técnica) ─────────────────────────────────────────

  Widget _buildDetailsGrid(MachineSlot slot, {required ColorScheme cs, required Color primary}) {
    final items = <_DetailItem>[];

    if (slot.productCategory != null)
      items.add(_DetailItem(Icons.category_outlined, 'Category',
          slot.productCategory!));
    if (slot.productBrand != null && slot.productBrand!.isNotEmpty)
      items.add(_DetailItem(Icons.verified_outlined, 'Brand',
          slot.productBrand!));
    if (slot.productSku != null && slot.productSku!.isNotEmpty)
      items.add(_DetailItem(Icons.qr_code_rounded, 'SKU', slot.productSku!));
    if (slot.productWeight != null)
      items.add(_DetailItem(Icons.scale_outlined, 'Weight',
          '${slot.productWeight} ${slot.productWeightUnit ?? 'g'}'));
    items.add(_DetailItem(Icons.point_of_sale_outlined, 'Slot',
        '#${slot.lineNumber}'));
    if (slot.productId != null)
      items.add(_DetailItem(Icons.tag_rounded, 'Product ID',
          '${slot.productId}'));

    if (items.isEmpty) return const SizedBox();

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
          children: items.map((item) => _DetailCard(item: item, cs: cs, primary: primary)).toList(),
        ),
      ],
    );
  }
}

// ─── Helper widgets ────────────────────────────────────────────────────────────

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
  const _DetailCard({required this.item, required this.cs, required this.primary});

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
                      color: cs.onSurface.withValues(alpha: 0.48), fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(item.value,
                  style: TextStyle(
                      color: cs.onSurface, fontSize: 13,
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
  final Color  color;
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
