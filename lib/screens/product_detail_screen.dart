import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/reyeah_service.dart';
import 'result_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final MachineSlot slot;
  const ProductDetailScreen({super.key, required this.slot});

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

  static const _blue = Color(0xFF007ACC);

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

  // ── Buy flows ─────────────────────────────────────────────────────────────

  Future<void> _buy() async {
    setState(() { _isLoading = true; _errorMsg = ''; });
    try {
      if (AppConfig.backendMode == 'reyeah') {
        await _buyReyeah();
      } else {
        await _buyVmsCloud();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMsg = _friendlyError(e.toString()); });
    }
  }

  Future<void> _buyVmsCloud() async {
    final result = await ApiService.claimPrice();
    if (!mounted) return;
    _navigateToResult(
      price:       result['price'] ?? '0.00',
      message:     result['message'] ?? 'Congratulations!',
      lineNumber:  int.tryParse(result['lineNumber'] ?? '') ?? widget.slot.lineNumber,
      machineNo:   result['machineNo']?.isNotEmpty == true
                   ? result['machineNo']! : widget.slot.lineNumber.toString(),
      lotteryCode: result['lotteryCode'] ?? '',
    );
  }

  Future<void> _buyReyeah() async {
    final externalId = widget.slot.externalId;
    if (externalId == null || externalId.isEmpty) {
      throw Exception('No product ID for this slot. Contact support.');
    }
    final orderNo = await ReyeahService.createOrder(machineLineProductId: externalId);
    await ReyeahService.shipment(orderNo);
    if (!mounted) return;
    _navigateToResult(
      price:       widget.slot.priceFormatted.replaceAll('\$', ''),
      message:     'Enjoy your ${widget.slot.productName}!',
      lineNumber:  widget.slot.lineNumber,
      machineNo:   AppConfig.vmMachineNo,
      lotteryCode: orderNo,
    );
  }

  void _navigateToResult({
    required String price, required String message,
    required int lineNumber, required String machineNo, required String lotteryCode,
  }) {
    Navigator.pushReplacement(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => ResultScreen(
        price: price, message: message, lineNumber: lineNumber,
        machineNo: machineNo, lotteryCode: lotteryCode,
        slot: widget.slot, skipCountdown: true,
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    ));
  }

  String _friendlyError(String raw) {
    if (raw.contains('unavailable'))   return 'No lottery available right now.';
    if (raw.contains('No product ID')) return raw.replaceFirst('Exception: ', '');
    if (raw.contains('Order'))         return 'Could not create order. Try again.';
    if (raw.contains('shipment'))      return 'Shipment confirmation failed. Try again.';
    return 'Connection error. Check your network.';
  }

  // ── Category color ────────────────────────────────────────────────────────

  Color _categoryColor(String? cat) {
    if (cat == null) return _blue;
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

    return Scaffold(
      backgroundColor: Colors.white,
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
                  _buildHeroImage(images, imgH, size),
                  // ── Info ────────────────────────────────────────────────
                  _buildInfoSheet(),
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
                        color: Colors.white.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.black87, size: 18),
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

  Widget _buildHeroImage(List<String> images, double height, Size size) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Galería
          images.isEmpty
              ? _buildImagePlaceholder()
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
                          Container(color: const Color(0xFFF0F4F8)),
                      errorWidget: (_, __, ___) => _buildImagePlaceholder(),
                    ),
                  ),
                ),

          // Gradiente inferior → funde con el panel blanco
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.white],
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
                          ? _blue : Colors.black.withValues(alpha: 0.25),
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

  Widget _buildImagePlaceholder() => Container(
    color: const Color(0xFFF0F4F8),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inventory_2_outlined,
          color: _blue.withValues(alpha: 0.35), size: 72),
      const SizedBox(height: 12),
      Text(widget.slot.productName,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black38, fontSize: 14)),
    ]),
  );

  // ── Info sheet ────────────────────────────────────────────────────────────

  Widget _buildInfoSheet() {
    final slot = widget.slot;
    final catColor = _categoryColor(slot.productCategory);
    final stockRatio = slot.maxStock > 0
        ? (slot.currentStock / slot.maxStock).clamp(0.0, 1.0) : 0.0;
    final stockColor = slot.isOutOfStock
        ? Colors.red
        : stockRatio <= 0.3 ? Colors.orange : Colors.green;

    return Container(
      color: Colors.white,
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
                  color: _blue,
                  icon: Icons.verified_outlined,
                ),
              _Chip(
                label: 'Slot #${slot.lineNumber}',
                color: Colors.black45,
                icon: Icons.point_of_sale_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Nombre del producto ──────────────────────────────────────
          Text(
            slot.productName,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),

          // ── Precio ──────────────────────────────────────────────────
          Semantics(
            label: 'Vending price: ${slot.priceFormatted}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_blue.withValues(alpha: 0.08), _blue.withValues(alpha: 0.03)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _blue.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Text(
                    slot.priceFormatted,
                    style: const TextStyle(
                      color: _blue,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'vending price',
                    style: TextStyle(color: Colors.black38, fontSize: 13),
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
                    backgroundColor: Colors.black.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation<Color>(stockColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Divider ──────────────────────────────────────────────────
          Divider(color: Colors.black.withValues(alpha: 0.07), height: 1),
          const SizedBox(height: 16),

          // ── Descripción ──────────────────────────────────────────────
          if (slot.productDescription != null &&
              slot.productDescription!.isNotEmpty) ...[
            const Text(
              'DESCRIPTION',
              style: TextStyle(
                color: Colors.black38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              slot.productDescription!,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 14,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ── Detalles adicionales ─────────────────────────────────────
          _buildDetailsGrid(slot),
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
                flex: 2,
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black54,
                      side: const BorderSide(color: Colors.black26),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Semantics(
                  label: 'Buy ${widget.slot.productName} for ${widget.slot.priceFormatted}',
                  button: true,
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _buy,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                        shadowColor: _blue.withValues(alpha: 0.4),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.shopping_cart_checkout_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('BUY NOW',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2)),
                            ]),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Center(
            child: Text('VMFS USA © 2026',
                style: TextStyle(color: Colors.black26, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ── Details grid (ficha técnica) ─────────────────────────────────────────

  Widget _buildDetailsGrid(MachineSlot slot) {
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
        const Text(
          'PRODUCT DETAILS',
          style: TextStyle(
            color: Colors.black38,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map((item) => _DetailCard(item: item)).toList(),
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
  const _DetailCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 15, color: const Color(0xFF007ACC)),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.label.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.black38, fontSize: 9,
                      fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 2),
              Text(item.value,
                  style: const TextStyle(
                      color: Colors.black87, fontSize: 13,
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
