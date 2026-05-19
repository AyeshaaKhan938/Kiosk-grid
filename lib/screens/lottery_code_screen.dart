import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

/// Pantalla de ingreso de cupón de lotería.
///
/// Flujo:
///   1. Usuario escribe su código (auto-mayúsculas)
///   2. Toca "VALIDATE"
///   3. Se llama al backend → animación de ruleta
///   4. Resultado: navega a ResultScreen con el precio y producto
///
/// Se puede abrir con o sin [slot] de contexto.
class LotteryCodeScreen extends StatefulWidget {
  /// Slot desde el que se abrió (opcional — viene de ProductDetailScreen).
  final MachineSlot? slot;

  const LotteryCodeScreen({super.key, this.slot});

  @override
  State<LotteryCodeScreen> createState() => _LotteryCodeScreenState();
}

enum _LotteryState { idle, validating, success, error }

class _LotteryCodeScreenState extends State<LotteryCodeScreen>
    with TickerProviderStateMixin {
  final _codeCtrl = TextEditingController();
  final _focusNode = FocusNode();

  _LotteryState _state = _LotteryState.idle;
  String _errorMsg = '';

  // ── Animación ruleta ──────────────────────────────────────────────────────
  late AnimationController _spinCtrl;
  late AnimationController _resultCtrl;
  late Animation<double>   _resultScale;
  late Animation<double>   _resultFade;

  bool get _canValidate =>
      _state == _LotteryState.idle && _codeCtrl.text.trim().length >= 4;

  @override
  void initState() {
    super.initState();

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _resultCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _resultScale = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _resultCtrl, curve: Curves.elasticOut));
    _resultFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _resultCtrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focusNode.dispose();
    _spinCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  // ── Validación ────────────────────────────────────────────────────────────

  Future<void> _validate() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    _focusNode.unfocus();
    setState(() { _state = _LotteryState.validating; _errorMsg = ''; });

    // Arrancar animación de ruleta
    _spinCtrl.repeat();

    try {
      final result = await ApiService.lookupCode(code);

      if (!mounted) return;

      if (result.alreadyRedeemed) {
        _showError('This code has already been redeemed.');
        return;
      }

      // Detener ruleta y mostrar animación de éxito
      _spinCtrl.stop();
      setState(() => _state = _LotteryState.success);
      await _resultCtrl.forward();

      if (!mounted) return;

      // Pequeña pausa para que se vea el éxito antes de navegar
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // Navegar a ResultScreen con los datos del premio
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => ResultScreen(
            price:       result.prizeAmount,
            message:     'You won ${result.prizeName} on ${result.productName}!',
            lineNumber:  result.lineNumber,
            machineNo:   result.machineNo,
            lotteryCode: result.code,
            tier:        result.tier,
            slot:        widget.slot,
            productName: result.productName,
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } on LotteryCodeException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Connection error. Check your network.');
    }
  }

  void _showError(String msg) {
    _spinCtrl.stop();
    _spinCtrl.reset();
    setState(() { _state = _LotteryState.error; _errorMsg = msg; });
  }

  void _resetToIdle() {
    setState(() { _state = _LotteryState.idle; _errorMsg = ''; });
    _resultCtrl.reset();
    _codeCtrl.clear();
    Future.delayed(const Duration(milliseconds: 100), () => _focusNode.requestFocus());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final bg      = Theme.of(context).scaffoldBackgroundColor;
    final primary = cs.primary;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Contenido: arriba = branding/animación · abajo = input
          SafeArea(
            child: Column(
              children: [
                // Mitad superior — animación + título
                Expanded(flex: 45, child: _buildTopPanel(cs: cs, bg: bg, primary: primary)),
                // Divisor
                Container(height: 1,
                    color: primary.withValues(alpha: 0.15)),
                // Mitad inferior — formulario
                Expanded(flex: 55, child: _buildBottomPanel(cs: cs, bg: bg, primary: primary)),
              ],
            ),
          ),

          // Back button
          Positioned(
            top: 12, left: 90,
            child: SafeArea(
              child: Semantics(
                label: 'Go back',
                button: true,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
                    ),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: cs.onSurface.withValues(alpha: 0.65), size: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Panel superior — icono centrado arriba, texto debajo ─────────────────

  Widget _buildTopPanel({required ColorScheme cs, required Color bg, required Color primary}) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono / animación
            _buildCenterAnimation(cs: cs, primary: primary),
            const SizedBox(height: 14),
            // Título
            Text('🎟  LOTTERY COUPON',
                style: TextStyle(color: cs.onSurface, fontSize: 15,
                    fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 6),
            // Descripción
            Text(
              widget.slot != null
                  ? 'Redeeming for: ${widget.slot!.productName}'
                  : 'Enter the code on your coupon to reveal your special price.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 12, height: 1.5),
            ),
            // Estado
            if (_state == _LotteryState.validating) ...[
              const SizedBox(height: 8),
              Text('Validating…',
                  style: TextStyle(color: primary,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
            if (_state == _LotteryState.success) ...[
              const SizedBox(height: 8),
              const Text('✅  Code accepted!',
                  style: TextStyle(color: Colors.greenAccent,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCenterAnimation({required ColorScheme cs, required Color primary}) {
    switch (_state) {
      case _LotteryState.validating:
        return _SpinningWheel(controller: _spinCtrl);

      case _LotteryState.success:
        return FadeTransition(
          opacity: _resultFade,
          child: ScaleTransition(
            scale: _resultScale,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.15),
                border: Border.all(color: Colors.greenAccent, width: 2.5),
              ),
              child: const Center(
                child: Icon(Icons.check_rounded, color: Colors.greenAccent, size: 40),
              ),
            ),
          ),
        );

      case _LotteryState.error:
        return Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.1),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 2),
          ),
          child: const Center(
            child: Icon(Icons.close_rounded, color: Colors.redAccent, size: 36),
          ),
        );

      case _LotteryState.idle:
        return Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                primary.withValues(alpha: 0.3),
                primary.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
                color: primary.withValues(alpha: 0.4), width: 2),
          ),
          child: const Center(
            child: Text('🎟', style: TextStyle(fontSize: 36)),
          ),
        );
    }
  }

  // ── Panel inferior (formulario) ──────────────────────────────────────────

  Widget _buildBottomPanel({required ColorScheme cs, required Color bg, required Color primary}) {
    return Container(
      color: bg,
      child: Center(
        child: SizedBox(
          width: 520, // ancho máximo — centrado en pantalla
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Input
                _buildCodeInput(cs: cs, primary: primary),
                if (_state == _LotteryState.error) ...[
                  const SizedBox(height: 8),
                  _buildErrorMsg(cs: cs, primary: primary),
                ],
                const SizedBox(height: 12),
                // Botón
                SizedBox(width: double.infinity, height: 48,
                    child: _buildValidateButton(cs: cs, primary: primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeInput({required ColorScheme cs, required Color primary}) {
    final enabled = _state == _LotteryState.idle || _state == _LotteryState.error;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _state == _LotteryState.error
              ? Colors.redAccent.withValues(alpha: 0.6)
              : primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
        color: cs.surfaceContainerHighest,
      ),
      child: TextField(
        controller: _codeCtrl,
        focusNode: _focusNode,
        enabled: enabled,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          UpperCaseTextFormatter(),
          LengthLimitingTextInputFormatter(20),
        ],
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 5,
          fontFamily: 'monospace',
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: 'XXXXXX',
          hintStyle: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.32),
            fontSize: 22,
            letterSpacing: 5,
          ),
          labelText: 'Enter lottery code',
          labelStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 14),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: _codeCtrl.text.isNotEmpty && enabled
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: cs.onSurface.withValues(alpha: 0.48)),
                  onPressed: () { _codeCtrl.clear(); setState(() {}); },
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) { if (_canValidate) _validate(); },
      ),
    );
  }

  Widget _buildErrorMsg({required ColorScheme cs, required Color primary}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMsg,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
          TextButton(
            onPressed: _resetToIdle,
            child: Text('Try again',
                style: TextStyle(color: primary, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildValidateButton({required ColorScheme cs, required Color primary}) {
    final loading = _state == _LotteryState.validating;
    final success = _state == _LotteryState.success;

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: (_canValidate && !loading && !success) ? _validate : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: success
              ? Colors.green
              : (_canValidate ? primary : cs.onSurface.withValues(alpha: 0.12)),
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: _canValidate ? 6 : 0,
        ),
        child: loading
            ? SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(color: cs.onPrimary, strokeWidth: 2.5))
            : success
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_rounded, size: 22),
                    SizedBox(width: 8),
                    Text('Validated!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ])
                : const Tooltip(
                    message: 'Validate your lottery code',
                    child: Text('VALIDATE CODE',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
      ),
    );
  }
}

// ─── UpperCaseTextFormatter ───────────────────────────────────────────────────

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue value) {
    return value.copyWith(text: value.text.toUpperCase());
  }
}

// ─── _SpinningWheel ───────────────────────────────────────────────────────────

/// Rueda giratoria mientras se valida el código.
class _SpinningWheel extends StatelessWidget {
  final AnimationController controller;
  const _SpinningWheel({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Transform.rotate(
          angle: controller.value * 2 * math.pi,
          child: SizedBox(
            width: 80, height: 80,
            child: CustomPaint(painter: _WheelPainter()),
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  static const _colors = [
    Color(0xFFFFD700), Color(0xFF007ACC), Color(0xFF00C853),
    Color(0xFFFF6B35), Color(0xFF9B59B6), Color(0xFFE74C3C),
    Color(0xFF1ABC9C), Color(0xFFF39C12),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweepAngle = (2 * math.pi) / _colors.length;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < _colors.length; i++) {
      paint.color = _colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweepAngle - math.pi / 2,
        sweepAngle,
        true,
        paint,
      );
    }

    // Centro blanco
    paint.color = Colors.white;
    canvas.drawCircle(center, radius * 0.28, paint);

    // Texto central
    final span = TextSpan(
      text: '🎟',
      style: TextStyle(fontSize: radius * 0.32),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_) => false;
}
