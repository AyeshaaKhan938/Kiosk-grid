import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import '../services/lottery_availability_service.dart';
import '../services/lottery_stock_service.dart';
import '../widgets/lottery_stock_shell.dart';
import '../widgets/onscreen_keypad.dart';
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
///   2. They tap their unique code on the floating on-screen keypad
///      (Reyeah tablets ship with no system IME installed, so we render
///      our own — centered on screen so customers don't have to reach down).
///   3. They tap the big red ENTER key on the keypad.
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
  final _codeCtrl    = TextEditingController();
  final _focusNode   = FocusNode();
  final _scrollCtrl  = ScrollController();

  _State _state = _State.idle;
  String _errorMsg = '';
  bool _keypadVisible = false;

  /// Result of the on-init availability check.
  ///   null   → still checking, show a small spinner
  ///   .available == true   → render the normal keypad flow
  ///   .available == false  → render the out-of-stock card instead, no keypad
  LotteryAvailability? _availability;

  bool get _canSubmit =>
      _state != _State.validating && _codeCtrl.text.trim().length >= 4;

  @override
  void initState() {
    super.initState();
    // Ask the backend whether any lottery-eligible slot has stock right
    // now. If not, swap the UI to an out-of-stock card so the customer
    // doesn't bother typing a code that would only return 503 NO_STOCK.
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final result = await LotteryAvailabilityService.check();
    if (mounted) setState(() => _availability = result);
  }

  void _openKeypad() {
    if (_state == _State.validating) return;
    setState(() => _keypadVisible = true);
  }

  void _closeKeypad() {
    if (!_keypadVisible) return;
    setState(() => _keypadVisible = false);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    if (LotteryStockService.instance.isOutOfStock) {
      _showError('Prizes are currently out of stock.');
      return;
    }

    _focusNode.unfocus();
    _closeKeypad();
    setState(() { _state = _State.validating; _errorMsg = ''; });

    try {
      final result = await ApiService.lookupCode(code);
      if (!mounted) return;

      if (result.alreadyRedeemed) {
        _showError('This code has already been redeemed.');
        return;
      }

      await LotteryStockService.instance.decrement();

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
    setState(() {
      _state = _State.error;
      _errorMsg = msg;
      _keypadVisible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: LotteryStockShell(
        child: SafeArea(
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

            // ── Availability gate ────────────────────────────────────
            // Loading: small spinner while the on-init check completes.
            if (_availability == null) {
              return Center(
                child: SizedBox(
                  width: scale * 0.08,
                  height: scale * 0.08,
                  child: const CircularProgressIndicator(
                    color: Color(0xFF007ACC),
                    strokeWidth: 3,
                  ),
                ),
              );
            }
            // Unavailable: every lottery-eligible slot is out of stock.
            // Skip the keypad UI entirely; show the out-of-stock card
            // with a Back button that returns the customer to idle.
            if (!_availability!.available) {
              return _OutOfStockCard(
                scale: scale,
                onBack: () => Navigator.pop(context),
              );
            }
            // ── Normal flow: the keypad + code entry layout ──────────

            return Stack(
              fit: StackFit.expand,
              children: [
                SingleChildScrollView(
                  controller: _scrollCtrl,
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: h),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.05,
                          vertical: h * 0.02,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                            Align(
                              alignment: Alignment.center,
                              child: IntrinsicWidth(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              height: scale * 0.42,
                              child: OverflowBox(
                                minWidth: 0,
                                maxWidth: double.infinity,
                                alignment: Alignment.center,
                                child: Transform.translate(
                                  offset: Offset(scale * 0.22, 0),
                                  child: Image.asset(
                                    'assets/images/tiger_paw_qr.png',
                                    height: scale * 0.42,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        _missing('tiger_paw_qr.png', scale),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                  right: w * 0.04, top: scale * 0.005),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '*Must be 18 or older to register',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: scale * 0.028,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Padding(
                              padding:
                                  EdgeInsets.only(bottom: scale * 0.02),
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
                            _CodeInput(
                              controller: _codeCtrl,
                              focusNode: _focusNode,
                              enabled: _state != _State.validating,
                              scale: scale,
                              onTap: _openKeypad,
                            ),
                            SizedBox(
                              height: scale * 0.07,
                              child: Center(
                                child: _StatusLine(
                                  state: _state,
                                  msg: _errorMsg,
                                  scale: scale,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (_keypadVisible)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _closeKeypad,
                      behavior: HitTestBehavior.opaque,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Center(
                          child: GestureDetector(
                            onTap: () {},
                            child: _KeypadPopup(
                              width: math.min(w * 0.82, scale * 1.05),
                              scale: scale * 0.68,
                              codeCtrl: _codeCtrl,
                              state: _state,
                              canSubmit: _canSubmit,
                              onChanged: () => setState(() {
                                if (_state == _State.error) {
                                  _state = _State.idle;
                                }
                              }),
                              onSubmit: _validate,
                              onClose: _closeKeypad,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  top: scale * 0.02,
                  left: scale * 0.03,
                  child: _BackButton(
                    scale: scale,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              ],
            );
          },
        ),
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

/// Compact centered popup — keyboard only; code field stays on main screen.
class _KeypadPopup extends StatelessWidget {
  final double width;
  final double scale;
  final TextEditingController codeCtrl;
  final _State state;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onClose;

  const _KeypadPopup({
    required this.width,
    required this.scale,
    required this.codeCtrl,
    required this.state,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(
          horizontal: scale * 0.04,
          vertical: scale * 0.035,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF121212).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(scale * 0.025),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: scale * 0.06,
              offset: Offset(0, scale * 0.02),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close_rounded,
                    color: Colors.white70, size: scale * 0.08),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            OnScreenKeypad(
              controller: codeCtrl,
              mode: KeypadMode.alphanumeric,
              scale: scale,
              enabled: state != _State.validating,
              maxLength: 20,
              onChanged: onChanged,
              onSubmit: canSubmit ? onSubmit : null,
            ),
          ],
        ),
      ),
    );
  }
}

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
  final VoidCallback onTap;

  const _CodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
      height: scale * 0.12,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: controller,
        focusNode:  focusNode,
        enabled:    enabled,
        // readOnly + showCursor + disabled interactive-selection means
        // the system IME is never asked to appear (which is the whole
        // point — Reyeah tablets don't have one). The user can still see
        // a blinking cursor at the end of their input so it feels live.
        readOnly: true,
        showCursor: true,
        enableInteractiveSelection: false,
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
      ),
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

class _BackButton extends StatelessWidget {
  final double scale;
  final VoidCallback onTap;
  const _BackButton({required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = scale * 0.11;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: Container(
          width:  size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Out-of-stock card — "IT'S A HIT!"
//
// Rendered in place of the code-entry keypad when the backend reports zero
// lottery-eligible slots in stock for this machine. Co-branded Chevrolet /
// Detroit Tigers layout matching the printed customer materials.
//
// Stateful because we run a short idle timer — if the customer walks away
// without tapping Back, we auto-pop back to the idle screen so the next
// customer doesn't walk up to an "OUT OF STOCK" screen stuck on display.
// ─────────────────────────────────────────────────────────────────────────────

class _OutOfStockCard extends StatefulWidget {
  final double scale;
  final VoidCallback onBack;

  const _OutOfStockCard({required this.scale, required this.onBack});

  @override
  State<_OutOfStockCard> createState() => _OutOfStockCardState();
}

class _OutOfStockCardState extends State<_OutOfStockCard> {
  Timer? _idleTimer;

  /// How long the out-of-stock card stays up before we auto-return to the
  /// idle ads. Long enough for someone to read the message, short enough
  /// that an unattended kiosk doesn't sit on this screen for hours.
  static const _kIdleTimeout = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleTimeout, widget.onBack);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;

    // Any touch on the card resets the idle timer — so a customer who's
    // actively reading or tapping around stays on screen longer.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdleTimer(),
      child: Stack(
        children: [
          // Centred branded message block.
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: scale * 0.08),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Co-branded Chevrolet header. Falls back to the
                  // dedicated co-branded asset if present, otherwise
                  // composes the Chevrolet logo + a "Detroit Tigers"
                  // partner caption so the message still looks intentional
                  // before the operator drops the final art in.
                  Image.asset(
                    'assets/images/chevrolet_tigers_logo.png',
                    height: scale * 0.18,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/chevrolet_header_logo.png',
                      height: scale * 0.13,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Text(
                        'CHEVROLET',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: scale * 0.07,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: scale * 0.012),
                  Text(
                    'Official Vehicle of the Detroit Tigers™',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: scale * 0.030,
                      letterSpacing: 0.4,
                    ),
                  ),

                  SizedBox(height: scale * 0.12),

                  // Big "IT'S A HIT!" headline.
                  Text(
                    "IT'S A HIT!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: scale * 0.14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      height: 1.0,
                    ),
                  ),

                  SizedBox(height: scale * 0.08),

                  // Two-paragraph explanatory copy.
                  Text(
                    'Our prizes were so\npopular that we’ve run out.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: scale * 0.045,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: scale * 0.04),
                  Text(
                    'Please check back the\nnext time you’re here\nfor a restock!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: scale * 0.045,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Back button — top-RIGHT corner on this screen (the lottery
          // entry screen uses top-left). Per the design mockup. Tap goes
          // straight back to the idle ads and cancels the auto-return
          // timer in dispose.
          Positioned(
            top: scale * 0.02,
            right: scale * 0.03,
            child: _BackButton(scale: scale, onTap: widget.onBack),
          ),
        ],
      ),
    );
  }
}

