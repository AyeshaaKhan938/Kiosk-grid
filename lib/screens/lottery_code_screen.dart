import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

/// Chevrolet / Detroit Tigers branded lottery code entry screen.
///
/// Sized off MediaQuery so the same widget tree looks balanced on the
/// dev preview (~400 × 700) AND on the kiosk's 45" vertical 1:2 panel
/// (e.g. 1080 × 2160). All paddings / font sizes / images are expressed
/// as fractions of width or height.
///
/// Customer flow:
///   1. They scan the box's QR → register with Chevy
///   2. They type the unique code into the big white input
///   3. They press the keyboard Enter / Done key (no on-screen submit
///      button — by design)
///   4. We validate and hand off to [ResultScreen] which dispenses + shows
///      the THANK YOU screen.
class LotteryCodeScreen extends StatefulWidget {
  final MachineSlot? slot;
  const LotteryCodeScreen({super.key, this.slot});

  @override
  State<LotteryCodeScreen> createState() => _LotteryCodeScreenState();
}

enum _State { idle, validating, error }

class _LotteryCodeScreenState extends State<LotteryCodeScreen> {
  final _codeCtrl  = TextEditingController();
  final _focusNode = FocusNode();

  _State _state = _State.idle;
  String _errorMsg = '';

  bool get _canSubmit =>
      _state != _State.validating && _codeCtrl.text.trim().length >= 4;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    _focusNode.unfocus();
    setState(() { _state = _State.validating; _errorMsg = ''; });

    try {
      final result = await ApiService.lookupCode(code);
      if (!mounted) return;

      if (result.alreadyRedeemed) {
        _showError('This code has already been redeemed.');
        return;
      }

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => ResultScreen(
            price:         result.prizeAmount,
            message:       result.productName,
            lineNumber:    result.lineNumber,
            machineNo:     result.machineNo,
            lotteryCode:   result.code,
            tier:          result.tier,
            slot:          widget.slot,
            productName:   result.productName,
            skipCountdown: true,
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } on LotteryCodeException catch (e) {
      if (mounted) _showError(e.message);
    } catch (_) {
      if (mounted) _showError('Connection error. Check the network.');
    }
  }

  void _showError(String msg) {
    setState(() { _state = _State.error; _errorMsg = msg; });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            // `scale` is the unit all fonts/icons/image sizes are computed
            // from. We use min(w, h / 1.8) so on a wider-but-not-taller
            // screen (where h is the bottleneck) widgets shrink and
            // everything still fits. On the production 1:2 portrait
            // kiosk (h ≈ 2w) min(w, h/1.8) ≈ w, so sizes are unaffected.
            final scale = math.min(w, h / 1.8);

            return Stack(
              children: [
                // Hidden admin back-exit (top-left 60×60).
                Positioned(
                  top: 0, left: 0, width: 60, height: 60,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox.expand(),
                  ),
                ),

                // SingleChildScrollView + ConstrainedBox(minHeight: h) +
                // IntrinsicHeight gives us "fill the viewport, use Spacers
                // to distribute extra space; if the intrinsic content is
                // taller than the viewport (very square / very short
                // screens), allow scrolling instead of clipping or
                // disappearing widgets".
                SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: h),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.05,
                          vertical:   h * 0.02,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header: wide CHEVROLET wordmark. Cap height
                            // so a wide logo can't dominate on square /
                            // short screens.
                            ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxHeight: scale * 0.15),
                              child: Image.asset(
                                'assets/images/chevrolet_header_logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => _missing(
                                    'chevrolet_header_logo.png', scale),
                              ),
                            ),
                            SizedBox(height: scale * 0.03),

                            // Centered instruction block, text left-aligned
                            // inside.
                            Align(
                              alignment: Alignment.center,
                              child: IntrinsicWidth(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _InstructionLine(
                                        num: '1.', verb: 'SCAN',
                                        rest: ' the QR code below',
                                        baseFont: scale * 0.05),
                                    SizedBox(height: scale * 0.008),
                                    _InstructionLine(
                                        num: '2.', verb: 'REGISTER',
                                        rest: ' with Chevy',
                                        baseFont: scale * 0.05),
                                    SizedBox(height: scale * 0.008),
                                    _InstructionLine(
                                        num: '3.', verb: 'ENTER',
                                        rest: ' your unique code below',
                                        baseFont: scale * 0.05),
                                    SizedBox(height: scale * 0.008),
                                    _InstructionLine(
                                        num: '4.', verb: 'COLLECT',
                                        rest: ' your item',
                                        baseFont: scale * 0.05),
                                    SizedBox(height: scale * 0.008),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.recycling_rounded,
                                            color: Colors.white,
                                            size: scale * 0.055),
                                        SizedBox(width: scale * 0.02),
                                        Text('Recycle the box',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: scale * 0.05,
                                              fontWeight: FontWeight.w500,
                                            )),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Flexible space above the paw.
                            const Spacer(),

                            // Tiger paw QR — sized big enough that the arm
                            // visibly extends past the right edge of the
                            // viewport. The image is composed
                            // QR-on-left, tiger-arm-on-right; we
                            // center-align it in the slot and translate
                            // right by ~1/4 of its own width so the QR
                            // (which sits ~25% from the image's left
                            // edge) lands at the screen's horizontal
                            // center while the arm extends off-screen.
                            // OverflowBox(maxWidth: ∞) lets that overflow
                            // happen without being clipped.
                            SizedBox(
                              width:  double.infinity,
                              height: scale * 0.42,
                              child: OverflowBox(
                                minWidth:  0,
                                maxWidth:  double.infinity,
                                alignment: Alignment.center,
                                child: Transform.translate(
                                  offset: Offset(scale * 0.22, 0),
                                  child: Image.asset(
                                    'assets/images/tiger_paw_qr.png',
                                    height: scale * 0.42,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => _missing(
                                        'tiger_paw_qr.png', scale),
                                  ),
                                ),
                              ),
                            ),

                            // Flexible space below the paw.
                            const Spacer(),

                            // Big bold prompt — two forced lines.
                            Padding(
                              padding: EdgeInsets.only(bottom: scale * 0.02),
                              child: Text(
                                'ENTER YOUR UNIQUE\nREDEMPTION CODE HERE:',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: scale * 0.07,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),

                            // White input field.
                            _CodeInput(
                              controller: _codeCtrl,
                              focusNode:  _focusNode,
                              enabled:    _state != _State.validating,
                              scale:      scale,
                              onChanged:  (_) => setState(() {
                                if (_state == _State.error) {
                                  _state = _State.idle;
                                }
                              }),
                              onSubmitted: (_) {
                                if (_canSubmit) _validate();
                              },
                            ),

                            // Compact status / error line.
                            SizedBox(
                              height: scale * 0.07,
                              child: Center(
                                child: _StatusLine(
                                    state: _state,
                                    msg: _errorMsg,
                                    scale: scale),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _missing(String fname, double scale) => Container(
        padding: EdgeInsets.all(scale * 0.03),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Save to:\nassets/images/$fname',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white54, fontSize: scale * 0.03,
              fontFamily: 'monospace'),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _InstructionLine extends StatelessWidget {
  final String num;
  final String verb;
  final String rest;
  final double baseFont;
  const _InstructionLine({
    required this.num,
    required this.verb,
    required this.rest,
    required this.baseFont,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(color: Colors.white, fontSize: baseFont, height: 1.3),
        children: [
          TextSpan(text: '$num  ',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          TextSpan(text: verb,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          TextSpan(text: rest,
              style: const TextStyle(fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

class _CodeInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final double scale;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _CodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.scale,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: scale * 0.12,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: controller,
        focusNode:  focusNode,
        enabled:    enabled,
        autofocus:  true,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.go,
        inputFormatters: [
          _UpperCase(),
          LengthLimitingTextInputFormatter(20),
        ],
        style: TextStyle(
          color: Colors.black,
          fontSize: scale * 0.075,
          fontWeight: FontWeight.w900,
          letterSpacing: scale * 0.008,
        ),
        textAlign: TextAlign.center,
        cursorColor: Colors.black,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged:   onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final _State state;
  final String msg;
  final double scale;
  const _StatusLine({
    required this.state,
    required this.msg,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    if (state == _State.validating) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: scale * 0.04, height: scale * 0.04,
            child: const CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2),
          ),
          SizedBox(width: scale * 0.025),
          Text('Validating…',
              style: TextStyle(
                color: Colors.white70,
                fontSize: scale * 0.032,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              )),
        ],
      );
    }
    if (state == _State.error) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: scale * 0.04),
          SizedBox(width: scale * 0.02),
          Flexible(
            child: Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: scale * 0.032,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) {
    return v.copyWith(text: v.text.toUpperCase());
  }
}
