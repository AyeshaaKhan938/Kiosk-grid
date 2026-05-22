import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/vending_machine_service.dart';

/// Chevrolet / Detroit Tigers branded post-redemption screen.
///
/// Sized off MediaQuery so the layout scales from the dev preview up to
/// the kiosk's 45" 1:2 portrait panel. No price card, no countdown — the
/// promo is free, so we fire dispense on launch and jump straight to
/// THANK YOU on success.
class ResultScreen extends StatefulWidget {
  final String price;
  final String message;
  final int? lineNumber;
  final String machineNo;
  final String lotteryCode;
  final String tier;
  final MachineSlot? slot;
  final String? productName;
  final bool skipCountdown;

  const ResultScreen({
    super.key,
    required this.price,
    required this.message,
    this.lineNumber,
    this.machineNo = '',
    this.lotteryCode = '',
    this.tier = '',
    this.slot,
    this.productName,
    this.skipCountdown = true,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

enum _Flow { dispensing, success, error, noSlot }

class _ResultScreenState extends State<ResultScreen> {
  _Flow _state = _Flow.dispensing;
  String _errorMsg = '';
  Timer? _returnTimer;

  @override
  void initState() {
    super.initState();
    if (widget.lineNumber == null) {
      _state = _Flow.noSlot;
      _returnTimer = Timer(const Duration(seconds: 4), _returnToIdle);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _safeDispense());
    }
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    super.dispose();
  }

  /// Outer wrapper so any unhandled throwable inside the dispense pipeline
  /// shows a readable error on screen instead of crashing the activity.
  Future<void> _safeDispense() async {
    try {
      await _dispense();
    } catch (e, stack) {
      // Log so we have a trail in `adb logcat`, then degrade to the
      // on-screen error state with the exception message so an admin
      // standing in front of the machine can read what went wrong.
      debugPrint('ResultScreen dispense crashed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _state = _Flow.error;
        _errorMsg = 'Dispense failed: $e';
      });
    }
  }

  Future<void> _dispense() async {
    SemanticsService.announce(
        'Dispensing your item, please wait.', TextDirection.ltr);

    final result = await VendingMachineService.dispenseProduct(
      lineNumber:      widget.lineNumber!,
      lotteryCode:     widget.lotteryCode,
      machineNo:       widget.machineNo,
      simulateSuccess: AppConfig.simulateDispense,
      onProgress:      (_) {},
    );

    // Best-effort scratch-card confirm. The function itself swallows its
    // own errors, but wrap the launch in try/catch as belt-and-suspenders
    // so a synchronous throw can't escape this method.
    if (widget.tier.isNotEmpty && widget.lotteryCode.isNotEmpty) {
      try {
        unawaited(ApiService.confirmScratchCard(
          code:        widget.lotteryCode,
          tier:        widget.tier,
          lineNumber:  widget.lineNumber!,
          prizeAmount: double.tryParse(widget.price) ?? 0.0,
          success:     result.status == DispenseStatus.success,
          error:       result.errorMessage,
        ));
      } catch (e) {
        debugPrint('confirmScratchCard threw synchronously: $e');
      }
    }

    if (!mounted) return;

    if (result.status == DispenseStatus.success) {
      SemanticsService.announce(
          'Thank you. Please collect your item below.', TextDirection.ltr);
      setState(() => _state = _Flow.success);
      _returnTimer = Timer(const Duration(seconds: 8), _returnToIdle);
    } else {
      setState(() {
        _state = _Flow.error;
        _errorMsg = result.errorMessage ?? 'Unknown error';
      });
    }
  }

  void _returnToIdle() {
    if (!mounted) return;
    try {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      debugPrint('returnToIdle navigation failed: $e');
    }
  }

  void _retry() {
    setState(() { _state = _Flow.dispensing; _errorMsg = ''; });
    _safeDispense();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    // `scale` is the unit all fonts/icons/image sizes are computed from.
    // Using min(w, h / 1.8) ensures widgets shrink when the screen is
    // shorter than ideal (e.g. wider-than-tall browser windows) so the
    // layout always fits. On the production 1:2 portrait kiosk
    // (h ≈ 2w) this equals min(w, ~1.1w) ≈ w — sizes unaffected.
    final scale = math.min(w, h / 1.8);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 0, left: 0, width: 60, height: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _returnToIdle,
                child: const SizedBox.expand(),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.05,
                vertical:   h * 0.03,
              ),
              child: _buildBody(w, h, scale),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(double w, double h, double scale) {
    switch (_state) {
      case _Flow.dispensing:
        return Column(
          children: [
            _ChevyTigersLockup(w: w, scale: scale),
            const Spacer(),
            SizedBox(
              width: scale * 0.15, height: scale * 0.15,
              child: const CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 4),
            ),
            SizedBox(height: scale * 0.03),
            Text(
              'DISPENSING YOUR ITEM…',
              style: TextStyle(
                color: Colors.white,
                fontSize: scale * 0.065,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: scale * 0.015),
            Text(
              widget.productName ?? widget.slot?.productName ?? '',
              style: TextStyle(
                color: Colors.white54,
                fontSize: scale * 0.04,
              ),
            ),
            const Spacer(),
          ],
        );

      case _Flow.success:
        return Column(
          children: [
            _ChevyTigersLockup(w: w, scale: scale),
            const Spacer(),
            // HUGE thank you. FittedBox prevents overflow on narrow widths.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'THANK YOU!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: scale * 0.18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  height: 1,
                ),
              ),
            ),
            const Spacer(),
            // Three-line collect message — matches the design layout.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'PLEASE\nCOLLECT YOUR\nITEM BELOW',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: scale * 0.105,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  height: 1.05,
                ),
              ),
            ),
            SizedBox(height: scale * 0.04),
            Text(
              'Returning to home in a few seconds…',
              style: TextStyle(color: Colors.white38, fontSize: scale * 0.028),
            ),
            SizedBox(height: scale * 0.01),
          ],
        );

      case _Flow.error:
        return Column(
          children: [
            _ChevyTigersLockup(w: w, scale: scale),
            const Spacer(),
            Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: scale * 0.2),
            SizedBox(height: scale * 0.02),
            Text(
              'DISPENSE FAILED',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: scale * 0.075,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: scale * 0.02),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.05),
              child: Text(
                _errorMsg,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: scale * 0.04),
              ),
            ),
            SizedBox(height: scale * 0.04),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PromoButton(label: 'TRY AGAIN', onTap: _retry,
                    primary: true, scale: scale),
                SizedBox(width: scale * 0.04),
                _PromoButton(label: 'HOME', onTap: _returnToIdle,
                    primary: false, scale: scale),
              ],
            ),
            const Spacer(),
          ],
        );

      case _Flow.noSlot:
        return Column(
          children: [
            _ChevyTigersLockup(w: w, scale: scale),
            const Spacer(),
            Icon(Icons.warning_amber_rounded,
                color: const Color(0xFFFFC107), size: scale * 0.2),
            SizedBox(height: scale * 0.02),
            Text(
              'NO ITEM ASSIGNED',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: scale * 0.075,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: scale * 0.02),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.06),
              child: Text(
                'Your code was accepted but no product is configured for it. '
                'Please notify staff.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: scale * 0.04),
              ),
            ),
            const Spacer(),
            Text(
              'Returning to home…',
              style: TextStyle(color: Colors.white38, fontSize: scale * 0.028),
            ),
            SizedBox(height: scale * 0.01),
          ],
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// CHEVROLET | D combined lockup with "Official Vehicle of the Detroit Tigers"
/// tagline. One image so the relative sizing of all three elements stays
/// pixel-perfect. Height capped via `scale` so a wide logo never dominates
/// on square / short screens.
class _ChevyTigersLockup extends StatelessWidget {
  final double w;
  final double scale;
  const _ChevyTigersLockup({required this.w, required this.scale});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: scale * 0.22),
      child: Padding(
        padding: EdgeInsets.only(top: scale * 0.01, bottom: scale * 0.02),
        child: Image.asset(
          'assets/images/chevrolet_tigers_lockup.png',
          width: w * 0.7,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            padding: EdgeInsets.all(scale * 0.03),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Save to:\nassets/images/chevrolet_tigers_lockup.png',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: scale * 0.03,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final double scale;
  const _PromoButton({
    required this.label,
    required this.onTap,
    required this.primary,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? const Color(0xFFFFC107) : Colors.transparent;
    final fg = primary ? Colors.black : Colors.white;
    return SizedBox(
      width:  scale * 0.4,
      height: scale * 0.11,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: primary
              ? null
              : const BorderSide(color: Colors.white54, width: 1.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: scale * 0.045,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}
