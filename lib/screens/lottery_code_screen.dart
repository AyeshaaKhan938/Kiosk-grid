import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

/// Chevrolet / Detroit Tigers branded lottery code entry screen.
///
/// Flow:
///   1. Customer scans their box's QR code → registers with Chevy
///   2. They type their unique redemption code into the input field
///   3. We hit the validation API
///   4. On success we hand off to [ResultScreen] which auto-dispenses
class LotteryCodeScreen extends StatefulWidget {
  /// Optional product slot context (when launched from a product detail page).
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

      // Hand off to ResultScreen which auto-dispenses + shows the THANK YOU
      // screen on success.
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => ResultScreen(
            price:       result.prizeAmount,
            message:     result.productName,
            lineNumber:  result.lineNumber,
            machineNo:   result.machineNo,
            lotteryCode: result.code,
            tier:        result.tier,
            slot:        widget.slot,
            productName: result.productName,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Hidden back gesture — top-left 60x60 (admin escape).
            Positioned(
              top: 0, left: 0, width: 60, height: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: const SizedBox.expand(),
              ),
            ),

            // Main content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── CHEVROLET wordmark + bowtie at top ─────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 32),
                    child: Image.asset(
                      'assets/images/chevrolet_logo_wide.png',
                      height: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const _MissingAsset(
                        label: 'chevrolet_logo_wide.png',
                      ),
                    ),
                  ),

                  // ── Numbered instructions ──────────────────────────────
                  const _InstructionLine(num: '1.', verb: 'SCAN',     rest: ' the QR code below'),
                  const SizedBox(height: 6),
                  const _InstructionLine(num: '2.', verb: 'REGISTER', rest: ' with Chevy'),
                  const SizedBox(height: 6),
                  const _InstructionLine(num: '3.', verb: 'ENTER',    rest: ' your unique code below'),
                  const SizedBox(height: 6),
                  const _InstructionLine(num: '4.', verb: 'COLLECT',  rest: ' your item'),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(Icons.recycling_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text('Recycle the box',
                          style: TextStyle(color: Colors.white, fontSize: 20,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),

                  // ── Tiger-paw + QR artwork ─────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Image.asset(
                          'assets/images/tiger_paw_qr.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const _MissingAsset(
                            label: 'tiger_paw_qr.png',
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Big bold prompt ────────────────────────────────────
                  const Text(
                    'ENTER YOUR UNIQUE\nREDEMPTION CODE HERE:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      height: 1.1,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Input field ───────────────────────────────────────
                  _CodeInput(
                    controller: _codeCtrl,
                    focusNode:  _focusNode,
                    enabled:    _state != _State.validating,
                    onChanged:  (_) => setState(() {
                      if (_state == _State.error) _state = _State.idle;
                    }),
                    onSubmitted: (_) { if (_canSubmit) _validate(); },
                  ),

                  // ── Submit button + status ────────────────────────────
                  const SizedBox(height: 18),
                  _SubmitArea(
                    state:    _state,
                    canSubmit: _canSubmit,
                    errorMsg: _errorMsg,
                    onSubmit: _validate,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _InstructionLine extends StatelessWidget {
  final String num;
  final String verb;
  final String rest;
  const _InstructionLine({required this.num, required this.verb, required this.rest});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 22, height: 1.3),
        children: [
          TextSpan(text: '$num  ',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          TextSpan(text: verb,
              style: const TextStyle(fontWeight: FontWeight.w900,
                  letterSpacing: 1.2)),
          TextSpan(text: rest, style: const TextStyle(fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

class _CodeInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _CodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
        inputFormatters: [
          _UpperCase(),
          LengthLimitingTextInputFormatter(20),
        ],
        style: const TextStyle(
          color: Colors.black,
          fontSize: 36,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
        ),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 16),
        ),
        onChanged:   onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _SubmitArea extends StatelessWidget {
  final _State state;
  final bool canSubmit;
  final String errorMsg;
  final VoidCallback onSubmit;
  const _SubmitArea({
    required this.state,
    required this.canSubmit,
    required this.errorMsg,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    if (state == _State.validating) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5)),
          SizedBox(width: 14),
          Text('Validating…',
              style: TextStyle(color: Colors.white70, fontSize: 16,
                  fontWeight: FontWeight.w600, letterSpacing: 1)),
        ],
      );
    }

    return Column(
      children: [
        if (state == _State.error) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(errorMsg,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: canSubmit ? onSubmit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canSubmit
                  ? const Color(0xFFFFC107) // Chevy gold
                  : Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.black,
              disabledForegroundColor: Colors.white38,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
            child: const Text(
              'SUBMIT',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MissingAsset extends StatelessWidget {
  final String label;
  const _MissingAsset({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, color: Colors.white38, size: 32),
          const SizedBox(height: 8),
          Text(
            'Save image to:\nassets/images/$label',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) {
    return v.copyWith(text: v.text.toUpperCase());
  }
}
