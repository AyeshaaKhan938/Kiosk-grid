import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../models/machine_slot.dart';
import '../services/app_config.dart';
import '../services/vending_machine_service.dart';

class ResultScreen extends StatefulWidget {
  final String price;
  final String message;

  /// Slot físico a dispensar (viene de la API de lotería).
  final int? lineNumber;

  /// Número de serie de la máquina (trazabilidad).
  final String machineNo;

  /// Código ganador (trazabilidad).
  final String lotteryCode;

  /// Slot seleccionado por el usuario (para mostrar nombre del producto).
  final MachineSlot? slot;

  /// Nombre del producto (fallback cuando slot es null — viene del lookup).
  final String? productName;

  /// Si true, omite el ring de auto-compra y dispensa de inmediato.
  /// Usar cuando el usuario ya tomó la decisión de comprar (Buy directo).
  final bool skipCountdown;

  const ResultScreen({
    super.key,
    required this.price,
    required this.message,
    this.lineNumber,
    this.machineNo = '',
    this.lotteryCode = '',
    this.slot,
    this.productName,
    this.skipCountdown = false,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

// Estados del flujo completo: precio → pago → despacho
enum _FlowState { showingPrice, paying, dispensing, success, error }

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  // ── Animaciones ───────────────────────────────────────────────────────────
  late AnimationController _entryController;
  late AnimationController _glowController;
  late AnimationController _countdownController;

  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _glowAnim;

  bool _showPrice = false;

  // ── Auto-compra: 10 s después de mostrar el precio ───────────────────────
  //   Si _canClaim → cuenta atrás → _startPayment() automático.
  //   El usuario puede cancelar durante esos 10 s.
  static const int _autoBuySeconds = 10;
  int _autoBuyRemaining = _autoBuySeconds;
  bool _autoBuyActive = true;

  // ── Estado del flujo ──────────────────────────────────────────────────────
  _FlowState _state = _FlowState.showingPrice;
  String _errorMsg = '';

  bool get _canClaim => widget.lineNumber != null;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeIn),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Placeholder para _countdownController — se reemplaza en _startCountdown()
    // Necesario porque AnimatedBuilder lo referencia antes del delayed de 300ms.
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Mostrar precio con animación de entrada
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _showPrice = true);
      _entryController.forward();

      if (widget.skipCountdown && _canClaim) {
        // Compra directa: dispensa inmediatamente sin ring de cuenta atrás
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) _startPayment();
        });
      } else {
        _startCountdown();
      }
    });
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  void _startCountdown() {
    // Reemplazar el placeholder por el controller real del auto-buy
    _countdownController.dispose();
    // _countdownController: barra de progreso del auto-buy (0 → 1 en 5 s)
    _countdownController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _autoBuySeconds),
    )..addListener(() {
        if (!_autoBuyActive) return;
        final remaining = _autoBuySeconds -
            (_countdownController.value * _autoBuySeconds).floor();
        if (mounted && remaining != _autoBuyRemaining) {
          setState(() => _autoBuyRemaining = remaining);
        }
      });

    _countdownController.forward().then((_) {
      if (mounted && _autoBuyActive) {
        if (_canClaim) {
          // ✅ Auto-arrancar compra cuando termina el contador
          _startPayment();
        } else {
          Navigator.pop(context);
        }
      }
    });
  }

  void _cancelAutoBuy() {
    _autoBuyActive = false;
    _countdownController.stop();
  }

  // ── Flujo de pago ─────────────────────────────────────────────────────────

  Future<void> _startPayment() async {
    if (_state != _FlowState.showingPrice) return;
    _cancelAutoBuy();

    SemanticsService.announce('Processing payment, please wait.', TextDirection.ltr);
    setState(() => _state = _FlowState.paying);

    // Simular procesamiento de pago (2.5 s)
    // En producción: integrar con cash acceptor / card reader hardware
    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;

    // Pago aprobado → iniciar despacho
    await _dispenseProduct();
  }

  // ── Despacho ──────────────────────────────────────────────────────────────

  Future<void> _dispenseProduct() async {
    SemanticsService.announce('Dispensing your product, please wait.', TextDirection.ltr);
    setState(() => _state = _FlowState.dispensing);

    final result = await VendingMachineService.dispenseProduct(
      lineNumber: widget.lineNumber!,
      lotteryCode: widget.lotteryCode,
      machineNo: widget.machineNo,
      simulateSuccess: AppConfig.simulateDispense,
      onProgress: (_) {},
    );

    if (!mounted) return;

    if (result.status == DispenseStatus.success) {
      SemanticsService.announce('Success! Please collect your product from the dispenser.', TextDirection.ltr);
      setState(() => _state = _FlowState.success);
      // Volver automáticamente al browser después de 5 s
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) Navigator.pop(context);
      });
    } else {
      setState(() {
        _state = _FlowState.error;
        _errorMsg = result.errorMessage ?? 'Unknown error';
      });
    }
  }

  void _retryFromError() {
    setState(() {
      _state = _FlowState.showingPrice;
      _autoBuyRemaining = _autoBuySeconds;
      _autoBuyActive = true;
    });
    _startCountdown();
  }

  void _extendTime() {
    _countdownController.stop();
    _countdownController.reset();
    setState(() { _autoBuyRemaining = 30; });
    _startCountdown();
    SemanticsService.announce(
        'Time extended. You have 30 more seconds.', TextDirection.ltr);
  }

  @override
  void dispose() {
    _entryController.dispose();
    _glowController.dispose();
    _countdownController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Contenido principal
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Cabecera ───────────────────────────────────────────
                  _buildHeader(),
                  const SizedBox(height: 32),

                  // ── Precio ganado (animado) ────────────────────────────
                  if (_showPrice) _buildPriceCard(),
                  if (!_showPrice)
                    const CircularProgressIndicator(color: Color(0xFF007ACC)),

                  const SizedBox(height: 36),

                  // ── Sección de acción según estado ─────────────────────
                  // AnimatedBuilder para que el ring del auto-buy se mueva suave
                  AnimatedBuilder(
                    animation: _countdownController,
                    builder: (_, __) => _buildActionSection(),
                  ),
                ],
              ),
            ),
          ),

          // Logo pequeño + nombre del producto
          Positioned(
            top: 20,
            left: 90,
            child: Row(
              children: [
                const Icon(Icons.storefront,
                    color: Color(0xFF007ACC), size: 24),
                const SizedBox(width: 8),
                Text(
                  widget.slot?.productName ?? widget.productName ?? 'VMFS USA',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Cabecera ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          '🎉  CONGRATULATIONS!',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 30,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.black54, fontSize: 17, letterSpacing: 0.5),
        ),
      ],
    );
  }

  // ── Tarjeta de precio ──────────────────────────────────────────────────────

  Widget _buildPriceCard() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (_, child) => Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 60, vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF007ACC), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF007ACC)
                      .withValues(alpha: _glowAnim.value),
                  blurRadius: 60,
                  spreadRadius: 10,
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF007ACC).withValues(alpha: 0.08),
                  const Color(0xFF007ACC).withValues(alpha: 0.03),
                ],
              ),
            ),
            child: child,
          ),
          child: Column(
            children: [
              const Text(
                'YOUR PRICE',
                style: TextStyle(
                  color: Colors.black38,
                  fontSize: 13,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '\$${widget.price}',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 76,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  height: 1,
                ),
              ),
              // Mostrar nombre del producto (slot o fallback del lookup)
              if (widget.slot != null || widget.productName != null) ...[
                const SizedBox(height: 6),
                Text(
                  'for ${widget.slot?.productName ?? widget.productName}',
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Sección de acciones ────────────────────────────────────────────────────

  Widget _buildActionSection() {
    switch (_state) {
      // ── 1. Precio ganado → auto-compra en 5 s ─────────────────────────
      case _FlowState.showingPrice:
        if (_canClaim) {
          // Tiene slot asignado → mostrar ring de auto-compra
          return Column(
            children: [
              // Ring countdown + label central
              _AutoBuyRing(
                progress: _countdownController.value,
                secondsLeft: _autoBuyRemaining,
                price: widget.price,
                onCancel: () {
                  _cancelAutoBuy();
                  Navigator.pop(context);
                },
                onBuyNow: _startPayment,
                onNeedMoreTime: _extendTime,
              ),
            ],
          );
        }
        // Sin lineNumber → solo mostrar precio y volver
        return Column(
          children: [
            const Text(
              'No product slot assigned',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.black54, size: 18),
              label: const Text(
                'Back to menu',
                style: TextStyle(color: Colors.black54, fontSize: 15),
              ),
            ),
          ],
        );

      // ── 2. Procesando pago ─────────────────────────────────────────────
      case _FlowState.paying:
        return _StatusCard(
          icon: const SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
                color: Color(0xFF007ACC), strokeWidth: 3),
          ),
          label: 'Processing payment…',
          sublabel: 'Please wait, do not remove your card',
          color: const Color(0xFF007ACC),
        );

      // ── 3. Despachando producto ────────────────────────────────────────
      case _FlowState.dispensing:
        return _StatusCard(
          icon: const SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
                color: Colors.greenAccent, strokeWidth: 3),
          ),
          label: 'Dispensing your product!',
          sublabel: 'The machine is preparing your item…',
          color: Colors.greenAccent,
        );

      // ── 4. Éxito ───────────────────────────────────────────────────────
      case _FlowState.success:
        return _StatusCard(
          icon: const Icon(Icons.check_circle_rounded,
              color: Colors.greenAccent, size: 54),
          label: 'Enjoy your product! 🎉',
          sublabel: 'Please collect it from the dispenser slot',
          color: Colors.greenAccent,
          extra: const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Returning to menu in 5 seconds…',
              style: TextStyle(color: Colors.black38, fontSize: 12),
            ),
          ),
        );

      // ── 5. Error ───────────────────────────────────────────────────────
      case _FlowState.error:
        return Column(
          children: [
            _StatusCard(
              icon: const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 54),
              label: 'Something went wrong',
              sublabel: _errorMsg,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _retryFromError,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007ACC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 36, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50)),
              ),
            ),
          ],
        );
    }
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

/// Ring de cuenta atrás para auto-compra.
///
/// Muestra un círculo de progreso que se consume en [_autoBuySeconds] segundos.
/// Al llegar a 0 el estado padre llama a [_startPayment] automáticamente.
/// El usuario puede cancelar o adelantar la compra tocando "Buy Now".
class _AutoBuyRing extends StatelessWidget {
  final double progress;       // 0.0 → 1.0 (del AnimationController)
  final int secondsLeft;
  final String price;
  final VoidCallback onCancel;
  final VoidCallback onBuyNow;
  final VoidCallback onNeedMoreTime;

  const _AutoBuyRing({
    required this.progress,
    required this.secondsLeft,
    required this.price,
    required this.onCancel,
    required this.onBuyNow,
    required this.onNeedMoreTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Ring con contador ────────────────────────────────────────────
        SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Fondo del ring (gris)
              CircularProgressIndicator(
                value: 1.0,
                strokeWidth: 7,
                color: Colors.white12,
              ),
              // Ring de progreso que se consume
              CircularProgressIndicator(
                value: 1.0 - progress,   // empieza lleno y se vacía
                strokeWidth: 7,
                color: const Color(0xFF00C853),
                strokeCap: StrokeCap.round,
              ),
              // Segundos en el centro
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$secondsLeft',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                    const Text(
                      's',
                      style: TextStyle(color: Colors.black38, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Texto de estado ──────────────────────────────────────────────
        Text(
          'Purchasing \$$price automatically…',
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),

        const SizedBox(height: 20),

        // ── Botón "Buy Now" (adelantar compra) ───────────────────────────
        Semantics(
          label: 'Buy now for \$$price',
          button: true,
          child: GestureDetector(
            onTap: onBuyNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFF00897B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C853).withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Buy Now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ── Cancelar ─────────────────────────────────────────────────────
        TextButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close_rounded, color: Colors.black38, size: 16),
          label: const Text(
            'Cancel',
            style: TextStyle(color: Colors.black38, fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onNeedMoreTime,
          icon: const Icon(Icons.more_time_rounded, color: Color(0xFF007ACC), size: 16),
          label: const Text('Need more time?',
              style: TextStyle(color: Color(0xFF007ACC), fontSize: 13)),
        ),
      ],
    );
  }
}

/// Tarjeta de estado (loading / success / error).
class _StatusCard extends StatelessWidget {
  final Widget icon;
  final String label;
  final String sublabel;
  final Color color;
  final Widget? extra;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: color.withValues(alpha: 0.4), width: 1.5),
        color: color.withValues(alpha: 0.05),
      ),
      child: Column(
        children: [
          SizedBox(width: 54, height: 54, child: Center(child: icon)),
          const SizedBox(height: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sublabel,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.black54, fontSize: 14),
          ),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}
