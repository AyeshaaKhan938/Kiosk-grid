import 'dart:async';
import 'package:flutter/material.dart';
import '../models/advertisement.dart';
import '../services/advertisement_service.dart';

/// Pantalla de salvapantallas — se muestra cuando el kiosk está inactivo.
///
/// Muestra los anuncios del slot `screensaver` en ciclo continuo.
/// Cualquier toque en la pantalla cierra el screensaver y regresa.
///
/// Uso recomendado: envolver toda la app con [IdleDetector], que llama a
/// [ScreensaverScreen.show] automáticamente tras el timeout.
class ScreensaverScreen extends StatefulWidget {
  final List<Advertisement> ads;

  const ScreensaverScreen({super.key, required this.ads});

  /// Muestra el screensaver sobre la pantalla actual.
  /// Devuelve cuando el usuario toca la pantalla.
  static Future<void> show(BuildContext context, List<Advertisement> ads) {
    return Navigator.push<void>(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ScreensaverScreen(ads: ads),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  State<ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends State<ScreensaverScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Timer? _slideTimer;
  late PageController _pageCtrl;

  // Opacidad para el texto de "toca para continuar"
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  List<Advertisement> get _ads => widget.ads;

  @override
  void initState() {
    super.initState();

    _pageCtrl = PageController();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    if (_ads.isNotEmpty) _startSlideTimer();
  }

  void _startSlideTimer() {
    _slideTimer?.cancel();
    _slideTimer = Timer(AdvertisementService.defaultSlideDuration, _nextSlide);
  }

  void _nextSlide() {
    if (!mounted || _ads.isEmpty) return;
    final next = (_currentIndex + 1) % _ads.length;
    setState(() => _currentIndex = next);
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
    _startSlideTimer();
  }

  void _dismiss() => Navigator.pop(context);

  @override
  void dispose() {
    _slideTimer?.cancel();
    _pageCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismiss,
      onPanDown: (_) => _dismiss(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _ads.isEmpty ? _buildFallback() : _buildCarousel(),
      ),
    );
  }

  // ── Sin anuncios: logo VMFS pulsante ──────────────────────────────────────

  Widget _buildFallback() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Color(0xFF0A1628), Colors.black],
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildVmfsLogo(),
              const SizedBox(height: 40),
              _buildTapHint(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVmfsLogo() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF007ACC),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF007ACC).withValues(alpha: 0.5),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'VMFS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'VMFS USA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap to start',
          style: TextStyle(color: Colors.white38, fontSize: 16, letterSpacing: 1.5),
        ),
      ],
    );
  }

  // ── Carrusel de anuncios ───────────────────────────────────────────────────

  Widget _buildCarousel() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Slides
        PageView.builder(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _ads.length,
          itemBuilder: (_, i) => _buildSlide(_ads[i]),
        ),

        // Overlay oscuro suave en bordes
        _buildVignetteOverlay(),

        // Indicadores de página (dots)
        if (_ads.length > 1)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: _buildDots(),
          ),

        // "Tap to continue"
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: _buildTapHint(),
        ),
      ],
    );
  }

  Widget _buildSlide(Advertisement ad) {
    if (ad.type == AdMediaType.image && ad.mediaUrl != null) {
      return Image.network(
        ad.mediaUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildSlideFallback(ad.title),
      );
    }
    // Para vídeo / HTML → placeholder con título (se puede extender después)
    return _buildSlideFallback(ad.title);
  }

  Widget _buildSlideFallback(String title) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF0A1628), Colors.black],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildVmfsLogo(),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVignetteOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.45),
          ],
        ),
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_ads.length, (i) {
        final active = i == _currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF007ACC)
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildTapHint() {
    return FadeTransition(
      opacity: _pulseAnim,
      child: const Text(
        '· TAP ANYWHERE TO CONTINUE ·',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          letterSpacing: 3,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── IdleDetector ─────────────────────────────────────────────────────────────

/// Envuelve un widget y detecta inactividad del usuario.
///
/// Cuando el usuario no toca la pantalla durante [timeout], llama a [onIdle].
/// Cada toque resetea el timer.
///
/// Ejemplo de uso en main.dart:
/// ```dart
/// home: IdleDetector(
///   onIdle: () async {
///     final ads = await AdvertisementService.fetchAds();
///     if (navigatorKey.currentContext != null) {
///       await ScreensaverScreen.show(navigatorKey.currentContext!, ads.screensaver);
///     }
///   },
///   child: ProductBrowserScreen(),
/// ),
/// ```
class IdleDetector extends StatefulWidget {
  final Widget child;
  final Duration timeout;
  final VoidCallback onIdle;

  const IdleDetector({
    super.key,
    required this.child,
    required this.onIdle,
    this.timeout = AdvertisementService.idleTimeout,
  });

  @override
  State<IdleDetector> createState() => _IdleDetectorState();
}

class _IdleDetectorState extends State<IdleDetector> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, widget.onIdle);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
