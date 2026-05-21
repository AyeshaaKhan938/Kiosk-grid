import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/vending_machine_service.dart';

/// Chevrolet / Detroit Tigers branded post-redemption screen.
///
/// On launch we immediately fire the dispense command for [lineNumber]
/// (no price, no countdown — the promo is free). On success we display
/// the THANK YOU + PLEASE COLLECT YOUR ITEM BELOW layout from the
/// Chevy promo. On error we show a simple retry panel.
class ResultScreen extends StatefulWidget {
  /// Kept for API compatibility with callers. Not shown on the Chevy promo.
  final String price;
  final String message;

  /// Physical slot to dispense from (from the lottery API).
  final int? lineNumber;
  final String machineNo;
  final String lotteryCode;

  /// Tier rolled client-side ("A" or "B"). Empty when not a scratch-card flow.
  final String tier;

  final MachineSlot? slot;
  final String? productName;

  /// Kept for API compatibility. The Chevy flow always skips countdown.
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
      // Fire the dispense as soon as the screen is on-screen.
      WidgetsBinding.instance.addPostFrameCallback((_) => _dispense());
    }
  }

  @override
  void dispose() {
    _returnTimer?.cancel();
    super.dispose();
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

    // Report outcome to Ten Point Media when this is a scratch-card flow.
    if (widget.tier.isNotEmpty && widget.lotteryCode.isNotEmpty) {
      unawaited(ApiService.confirmScratchCard(
        code:        widget.lotteryCode,
        tier:        widget.tier,
        lineNumber:  widget.lineNumber!,
        prizeAmount: double.tryParse(widget.price) ?? 0.0,
        success:     result.status == DispenseStatus.success,
        error:       result.errorMessage,
      ));
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
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _retry() {
    setState(() { _state = _Flow.dispensing; _errorMsg = ''; });
    _dispense();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Top-left hidden tap to bail out (matches idle screen pattern).
            Positioned(
              top: 0, left: 0, width: 60, height: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _returnToIdle,
                child: const SizedBox.expand(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _Flow.dispensing:
        return Column(
          children: [
            const _ChevyTigersLockup(),
            const Spacer(),
            const SizedBox(
              width: 56, height: 56,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            const Text(
              'DISPENSING YOUR ITEM…',
              style: TextStyle(color: Colors.white, fontSize: 26,
                  fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            Text(
              widget.productName ?? widget.slot?.productName ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const Spacer(),
          ],
        );

      case _Flow.success:
        return const Column(
          children: [
            _ChevyTigersLockup(),
            Spacer(),
            Text(
              'THANK YOU!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 84,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                height: 1,
              ),
            ),
            Spacer(),
            Text(
              'PLEASE COLLECT YOUR\nITEM BELOW',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                height: 1.1,
              ),
            ),
            SizedBox(height: 32),
            Text(
              'Returning to home in a few seconds…',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            SizedBox(height: 16),
          ],
        );

      case _Flow.error:
        return Column(
          children: [
            const _ChevyTigersLockup(),
            const Spacer(),
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 72),
            const SizedBox(height: 20),
            const Text(
              'DISPENSE FAILED',
              style: TextStyle(color: Colors.redAccent, fontSize: 32,
                  fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PromoButton(
                  label: 'TRY AGAIN',
                  onTap:  _retry,
                  primary: true,
                ),
                const SizedBox(width: 16),
                _PromoButton(
                  label: 'HOME',
                  onTap: _returnToIdle,
                  primary: false,
                ),
              ],
            ),
            const Spacer(),
          ],
        );

      case _Flow.noSlot:
        return const Column(
          children: [
            _ChevyTigersLockup(),
            Spacer(),
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFFC107), size: 72),
            SizedBox(height: 20),
            Text(
              'NO ITEM ASSIGNED',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 32,
                  fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Your code was accepted but no product is configured for it. '
                'Please notify staff.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            Spacer(),
            Text(
              'Returning to home…',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            SizedBox(height: 16),
          ],
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable building blocks
// ─────────────────────────────────────────────────────────────────────────────

/// The CHEVROLET | D combined logo with "Official Vehicle of the Detroit Tigers"
/// tagline. Single image asset for cleanest rendering.
class _ChevyTigersLockup extends StatelessWidget {
  const _ChevyTigersLockup();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Image.asset(
        'assets/images/chevrolet_tigers_lockup.png',
        height: 130,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Save image to:\nassets/images/chevrolet_tigers_lockup.png',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12,
                fontFamily: 'monospace'),
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
  const _PromoButton({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? const Color(0xFFFFC107) : Colors.transparent;
    final fg = primary ? Colors.black : Colors.white;
    return SizedBox(
      width: 180, height: 56,
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
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}
