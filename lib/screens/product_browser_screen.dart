import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/advertisement.dart';
import '../models/machine_slot.dart';
import '../services/advertisement_service.dart';
import '../services/app_config.dart';
import '../services/slot_service.dart';
import 'admin_config_screen.dart';
import 'idle_screen.dart';
import 'lottery_code_screen.dart';
import 'product_detail_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constantes del carousel
// ─────────────────────────────────────────────────────────────────────────────
const double _kCardSpacing  = 10.0;
const double _kSpeedPxSec   = 48.0; // px/segundo — lento y legible
const double _kSidePad      = 90.0; // padding lateral global

// ─────────────────────────────────────────────────────────────────────────────
// ProductBrowserScreen
// ─────────────────────────────────────────────────────────────────────────────
class ProductBrowserScreen extends StatefulWidget {
  const ProductBrowserScreen({super.key});

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

  static const int _numRows = 3;

  @override
  void initState() {
    super.initState();
    _adCtrl   = PageController();
    _demoCtrl = PageController();
    _loadSlots();
    _loadAds();
    _startDemoTimer();
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
      if (mounted && ads.top.isNotEmpty) {
        setState(() => _topAds = ads.top);
        _startAdTimer();
      }
    } catch (_) {}
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
      pageBuilder: (_, a, __) => ProductDetailScreen(slot: slot),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 280),
    ));
  }

  void _openLotteryCode() {
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => const LotteryCodeScreen(),
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 380),
    ));
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

    // Banner: menos alto en portrait para dejar espacio a los productos
    final adHeight = isPortrait ? size.height * 0.21 : size.height * 0.26;

    // ~5 productos visibles: ancho = (pantalla - 2×sidePad - gaps) / 5
    // El 0.2 extra hace peek del 6° producto, indicando que hay más
    final cardWidth = (size.width - 2 * _kSidePad - 5.2 * _kCardSpacing) / 5.2;

    final cs      = Theme.of(context).colorScheme;
    final bg      = Theme.of(context).scaffoldBackgroundColor;
    final primary = cs.primary;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildHeader(cs: cs, bg: bg, primary: primary),
          // ── Banner + botón Lottery centrado ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kSidePad, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: adHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildBanner(primary: primary),
                    // Degradado inferior
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent,
                              Colors.black.withValues(alpha: 0.70)],
                          ),
                        ),
                      ),
                    ),
                    // Lottery button — solo si hay token configurado
                    if (AppConfig.lotteryToken.isNotEmpty)
                      Center(child: _LotteryCouponButton(onTap: _openLotteryCode)),
                    // Dots demo
                    if (_topAds.isEmpty)
                      Positioned(
                        bottom: 8, left: 0, right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_demoSlides.length, (i) =>
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _demoIndex ? 18 : 6, height: 6,
                              decoration: BoxDecoration(
                                color: i == _demoIndex
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            )),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _buildProductsLabel(cs: cs, bg: bg, primary: primary),
          Expanded(child: _buildAllRows(cardWidth, cs: cs, primary: primary)),
          _buildBackBar(cs: cs, bg: bg),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader({required ColorScheme cs, required Color bg, required Color primary}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _kSidePad, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _onSecretTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('VMFS',
                  style: TextStyle(color: cs.onPrimary,
                      fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 2)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_data?.machineName ?? 'VMFS USA',
                style: TextStyle(color: cs.onSurface,
                    fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: 'Refresh product list',
              onPressed: _loadSlots,
              icon: Icon(Icons.refresh_rounded,
                  color: cs.onSurface.withValues(alpha: 0.65), size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            label: 'Open admin settings',
            button: true,
            child: SizedBox(
              width: 48,
              height: 48,
              child: GestureDetector(
                onTap: () => showAdminPinDialog(context),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: primary.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.settings_outlined,
                        color: primary, size: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Banner ────────────────────────────────────────────────────────────────

  Widget _buildBanner({required Color primary}) {
    if (_topAds.isNotEmpty) {
      return Stack(fit: StackFit.expand, children: [
        PageView.builder(
          controller: _adCtrl,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _topAds.length,
          itemBuilder: (_, i) {
            final ad = _topAds[i];
            if (ad.type == AdMediaType.image && ad.mediaUrl != null) {
              return CachedNetworkImage(imageUrl: ad.mediaUrl!, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: const Color(0xFF0A1628)),
                  errorWidget: (_, __, ___) => _adFallback(ad.title));
            }
            return _adFallback(ad.title);
          },
        ),
        if (_topAds.length > 1)
          Positioned(
            bottom: 8, left: 0, right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_topAds.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _adIndex ? 16 : 6, height: 6,
                  decoration: BoxDecoration(
                    color: i == _adIndex
                        ? primary
                        : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ))),
          ),
      ]);
    }
    return PageView.builder(
      controller: _demoCtrl,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _demoSlides.length,
      itemBuilder: (_, i) => _DemoBannerSlide(slide: _demoSlides[i]),
    );
  }

  Widget _adFallback(String title) => Container(
    color: const Color(0xFF0A1628),
    child: Center(child: Text(title,
        style: const TextStyle(color: Colors.white54, fontSize: 14))),
  );

  // ── Products label ────────────────────────────────────────────────────────

  Widget _buildProductsLabel({required ColorScheme cs, required Color bg, required Color primary}) {
    final count = _data?.slots.where((s) => s.isAvailable).length ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _kSidePad, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          Icon(Icons.grid_view_rounded, color: primary, size: 13),
          const SizedBox(width: 6),
          Text('PRODUCTS',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 10,
                  fontWeight: FontWeight.w600, letterSpacing: 2)),
          const SizedBox(width: 8),
          if (count > 0)
            Text('$count available',
                style: TextStyle(
                    color: primary.withValues(alpha: 0.7),
                    fontSize: 10)),
          const Spacer(),
          Icon(Icons.arrow_forward_rounded, color: cs.onSurface.withValues(alpha: 0.48), size: 11),
          const SizedBox(width: 2),
          Icon(Icons.arrow_back_rounded, color: cs.onSurface.withValues(alpha: 0.48), size: 11),
          const SizedBox(width: 2),
          Icon(Icons.arrow_forward_rounded, color: cs.onSurface.withValues(alpha: 0.48), size: 11),
        ],
      ),
    );
  }

  // ── All rows ──────────────────────────────────────────────────────────────

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

  Widget _buildBackBar({required ColorScheme cs, required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _kSidePad, vertical: 7),
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
