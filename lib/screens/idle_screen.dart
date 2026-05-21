import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/advertisement.dart';
import '../services/advertisement_service.dart';
import '../services/update_checker.dart';
import '../services/update_service.dart';
import 'admin_config_screen.dart';
import 'lottery_code_screen.dart';

/// Pantalla idle/screensaver del kiosk.
///
/// Estado de reposo: anuncios a pantalla completa con auto-rotación.
/// Tap en cualquier lugar → abre [LotteryCodeScreen] para que el cliente
/// ingrese el código del cupón directamente. No hay catálogo de productos
/// intermedio — el flujo es: ads → código → resultado.
class IdleScreen extends StatefulWidget {
  const IdleScreen({super.key});

  @override
  State<IdleScreen> createState() => _IdleScreenState();
}

class _IdleScreenState extends State<IdleScreen>
    with TickerProviderStateMixin {

  // ── Anuncios del backend ──────────────────────────────────────────────────
  List<Advertisement> _backendAds = [];
  int   _adIndex = 0;
  Timer? _adTimer;
  late PageController _pageCtrl;

  // ── Secret admin gesture (5 taps in the top-left corner within 2s) ────────
  int       _secretTaps = 0;
  DateTime? _lastSecretTap;

  // ── Slides demo (usados cuando no hay anuncios del backend) ───────────────
  static const List<_DemoSlide> _demoSlides = [
    _DemoSlide(
      title: 'PREMIUM SNACKS',
      subtitle: 'Over 15 snacks & candies to choose from',
      imageUrl: 'https://picsum.photos/seed/snacks-chips/1280/800',
      gradientColors: [Color(0xFFFF6B35), Color(0xFF1A0A00)],
    ),
    _DemoSlide(
      title: 'COLD BEVERAGES',
      subtitle: 'Stay refreshed — sodas, water, energy drinks',
      imageUrl: 'https://picsum.photos/seed/beverages-cold/1280/800',
      gradientColors: [Color(0xFF0066CC), Color(0xFF000820)],
    ),
    _DemoSlide(
      title: 'TECH ACCESSORIES',
      subtitle: 'Cables, chargers, earbuds — always in stock',
      imageUrl: 'https://picsum.photos/seed/tech-gadgets/1280/800',
      gradientColors: [Color(0xFF007ACC), Color(0xFF000A14)],
    ),
    _DemoSlide(
      title: 'HEALTH & WELLNESS',
      subtitle: 'Hand sanitizer, pain relief and more',
      imageUrl: 'https://picsum.photos/seed/health-wellness/1280/800',
      gradientColors: [Color(0xFF00AA66), Color(0xFF001A0D)],
    ),
    _DemoSlide(
      title: 'VMFS USA KIOSK',
      subtitle: 'Touch anywhere to browse all products',
      imageUrl: 'https://picsum.photos/seed/vending-kiosk/1280/800',
      gradientColors: [Color(0xFF6600CC), Color(0xFF0A0014)],
      isHighlight: true,
    ),
  ];

  // ── Animaciones ───────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  late AnimationController _slideTextCtrl;
  late Animation<Offset>   _slideTextAnim;

  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _slideTextCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideTextAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideTextCtrl, curve: Curves.easeOut));

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _loadAds();
    _startDemoTimer();
    _slideTextCtrl.forward();
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    _pageCtrl.dispose();
    _pulseCtrl.dispose();
    _slideTextCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAds() async {
    try {
      final ads = await AdvertisementService.fetchAds();
      if (mounted) {
        final all = [...ads.screensaver, ...ads.top];
        if (all.isNotEmpty) {
          setState(() => _backendAds = all);
          _startAdTimer();
        }
      }
    } catch (_) {}
  }

  void _startAdTimer() {
    _adTimer?.cancel();
    _adTimer = Timer.periodic(AdvertisementService.defaultSlideDuration, (_) {
      if (!mounted || _backendAds.isEmpty) return;
      _goToNextSlide(_backendAds.length);
    });
  }

  void _startDemoTimer() {
    if (_backendAds.isNotEmpty) return; // ya hay anuncios del backend
    _adTimer?.cancel();
    _adTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _backendAds.isNotEmpty) return;
      _goToNextSlide(_demoSlides.length);
    });
  }

  void _goToNextSlide(int count) {
    final next = (_adIndex + 1) % count;
    setState(() => _adIndex = next);
    _pageCtrl.animateToPage(next,
        duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
    _slideTextCtrl
      ..reset()
      ..forward();
  }

  // ── Hidden admin entry: 5 taps in top-left corner within 2 seconds ────────
  void _onSecretTap() {
    final now = DateTime.now();
    if (_lastSecretTap != null && now.difference(_lastSecretTap!).inSeconds > 2) {
      _secretTaps = 0;
    }
    _lastSecretTap = now;
    if (++_secretTaps >= 5) {
      _secretTaps = 0;
      showAdminPinDialog(context);
    }
  }

  // ── Tap → LotteryCodeScreen (push, not replace — so back returns to ads) ──
  void _onTap() {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, animation, __) => const LotteryCodeScreen(),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 350),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final useDemo = _backendAds.isEmpty;
    final slideCount = useDemo ? _demoSlides.length : _backendAds.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Semantics(
        label: 'VMFS USA vending machine kiosk. Touch anywhere to enter your lottery code.',
        button: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base layer: full-screen tappable region → lottery code entry
            GestureDetector(
              onTap: _onTap,
              behavior: HitTestBehavior.opaque,
              child: _buildSlideStack(useDemo: useDemo, slideCount: slideCount),
            ),

            // Invisible admin entry — top-left 60x60 area, 5 taps within 2s.
            // Sits above the main GestureDetector so taps here don't open
            // the lottery screen.
            Positioned(
              top: 0,
              left: 0,
              width: 60,
              height: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onSecretTap,
                child: const SizedBox.expand(),
              ),
            ),

            // Update-available badge — top-right, only visible when
            // UpdateChecker has discovered a new APK. Tapping it opens
            // the admin PIN flow so the operator can review/install.
            Positioned(
              top: 12, right: 12,
              child: SafeArea(
                child: ValueListenableBuilder<UpdateInfo?>(
                  valueListenable: UpdateChecker.instance.notifier,
                  builder: (_, info, __) {
                    if (info == null) return const SizedBox.shrink();
                    return _UpdateBadge(
                      versionName: info.versionName,
                      onTap: () => showAdminPinDialog(context),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideStack({required bool useDemo, required int slideCount}) {
    return Stack(
          fit: StackFit.expand,
          children: [
            // ── Carrusel de slides ────────────────────────────────────────
            PageView.builder(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: slideCount,
              itemBuilder: (_, i) => useDemo
                  ? _DemoSlideWidget(
                      slide:       _demoSlides[i % _demoSlides.length],
                      shimmerCtrl: _shimmerCtrl,
                    )
                  : _BackendAdWidget(ad: _backendAds[i]),
            ),

            // ── Gradiente inferior ────────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 220,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                  ),
                ),
              ),
            ),

            // ── Logo VMFS ─────────────────────────────────────────────────
            Positioned(
              top: 20, left: 90,
              child: SafeArea(
                child: _VmfsLogo(),
              ),
            ),

            // ── Texto animado del slide actual ────────────────────────────
            if (useDemo)
              Positioned(
                bottom: 90, left: 90, right: 90,
                child: SlideTransition(
                  position: _slideTextAnim,
                  child: FadeTransition(
                    opacity: _slideTextCtrl,
                    child: _SlideInfo(slide: _demoSlides[_adIndex % _demoSlides.length]),
                  ),
                ),
              ),

            // ── Dots ──────────────────────────────────────────────────────
            if (slideCount > 1)
              Positioned(
                bottom: 50, left: 0, right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(slideCount, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width:  i == _adIndex ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _adIndex
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )),
                ),
              ),

            // ── CTA pulsante ──────────────────────────────────────────────
            Positioned(
              bottom: 14, left: 0, right: 0,
              child: FadeTransition(
                opacity: _pulseAnim,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_rounded, color: Colors.white70, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'TOUCH TO ENTER YOUR LOTTERY CODE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
  }
}

// ─── Demo slide data ──────────────────────────────────────────────────────────

class _DemoSlide {
  final String title;
  final String subtitle;
  final String imageUrl;
  final List<Color> gradientColors;
  final bool isHighlight;
  const _DemoSlide({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.gradientColors,
    this.isHighlight = false,
  });
}

// ─── Demo slide widget ────────────────────────────────────────────────────────

class _DemoSlideWidget extends StatelessWidget {
  final _DemoSlide slide;
  final AnimationController shimmerCtrl;
  const _DemoSlideWidget({required this.slide, required this.shimmerCtrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Imagen de fondo (con caché en disco/memoria)
        CachedNetworkImage(
          imageUrl: slide.imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              Container(color: slide.gradientColors.last),
          errorWidget: (_, __, ___) =>
              Container(color: slide.gradientColors.last),
        ),

        // Gradiente sobre la imagen
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                slide.gradientColors[0].withValues(alpha: 0.88),
                slide.gradientColors[1].withValues(alpha: 0.55),
                Colors.transparent,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),

        // Gradiente vertical inferior
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
              stops: [0.5, 1.0],
            ),
          ),
        ),

        // Shimmer line (simula "video scanning")
        if (slide.isHighlight)
          AnimatedBuilder(
            animation: shimmerCtrl,
            builder: (_, __) {
              final x = shimmerCtrl.value;
              return Positioned(
                top: 0, bottom: 0,
                left: MediaQuery.of(context).size.width * x - 60,
                child: Container(
                  width: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

// ─── Slide info overlay ───────────────────────────────────────────────────────

class _SlideInfo extends StatelessWidget {
  final _DemoSlide slide;
  const _SlideInfo({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slide.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          slide.subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 15,
            letterSpacing: 0.5,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

// ─── Backend ad widget ────────────────────────────────────────────────────────

class _BackendAdWidget extends StatelessWidget {
  final Advertisement ad;
  const _BackendAdWidget({required this.ad});

  @override
  Widget build(BuildContext context) {
    if (ad.type == AdMediaType.image && ad.mediaUrl != null) {
      return Image.network(ad.mediaUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(ad.title));
    }
    return _fallback(ad.title);
  }

  Widget _fallback(String title) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF001230), Colors.black],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Text(title,
          style: const TextStyle(color: Colors.white38, fontSize: 20)),
    ),
  );
}

// ─── VMFS Logo ────────────────────────────────────────────────────────────────

class _VmfsLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF007ACC),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007ACC).withValues(alpha: 0.55),
            blurRadius: 20,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Text(
        'VMFS USA',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 17,
          letterSpacing: 2.5,
        ),
      ),
    );
  }
}

/// Small "Update available — v X.X.X" pill shown on the idle screen when
/// UpdateChecker has discovered a new APK. Tap routes through the admin
/// PIN gate so customers can't trigger an install.
class _UpdateBadge extends StatelessWidget {
  final String versionName;
  final VoidCallback onTap;
  const _UpdateBadge({required this.versionName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF388E3C).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF388E3C).withValues(alpha: 0.5),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.system_update_rounded,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                'Update available · v$versionName',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
