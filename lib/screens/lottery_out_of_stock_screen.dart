import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'admin_config_screen.dart';

/// Fullscreen overlay when lottery prize stock reaches zero.
///
/// Co-branded Chevrolet / Detroit Tigers "IT'S A HIT!" layout. Everything is
/// sized off `scale = min(width, height / 1.8)` so the same widget tree looks
/// balanced on the dev preview (~400 × 700) AND on the kiosk's 45" vertical
/// 1:2 panel (e.g. 1080 × 2160).
///
/// This overlay is painted on top of the idle/code screens by
/// [LotteryStockShell], which means it also covers the idle screen's hidden
/// admin gesture. Without its own escape hatch an operator would be locked
/// out of the admin panel whenever the machine is out of stock — so we
/// replicate the same secret gesture here: 5 taps in the top-left corner
/// within 2 seconds opens the admin PIN dialog.
class LotteryOutOfStockScreen extends StatefulWidget {
  const LotteryOutOfStockScreen({super.key});

  @override
  State<LotteryOutOfStockScreen> createState() =>
      _LotteryOutOfStockScreenState();
}

class _LotteryOutOfStockScreenState extends State<LotteryOutOfStockScreen> {
  // ── Secret admin gesture (5 taps in the top-left corner within 2s) ────────
  int _secretTaps = 0;
  DateTime? _lastSecretTap;

  void _onSecretTap() {
    final now = DateTime.now();
    if (_lastSecretTap != null &&
        now.difference(_lastSecretTap!).inSeconds > 2) {
      _secretTaps = 0;
    }
    _lastSecretTap = now;
    if (++_secretTaps >= 5) {
      _secretTaps = 0;
      showAdminPinDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final scale = math.min(w, h / 1.8);

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.06),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: h * 0.08),

                      // Co-branded Chevrolet bowtie | Detroit Tigers "D"
                      // lockup with the "Official Vehicle…" caption baked in.
                      Image.asset(
                        'assets/images/chevrolet_tigers_lockup.png',
                        width: w * 0.82,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            _LogoFallback(scale: scale),
                      ),

                      SizedBox(height: h * 0.10),

                      // Big "IT'S A HIT!" headline. FittedBox guards against
                      // horizontal overflow on the narrow dev preview.
                      _HitHeadline(scale: scale),

                      SizedBox(height: h * 0.055),

                      Text(
                        'Our prizes were so\npopular that we\'ve run out.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: scale * 0.052,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),

                      SizedBox(height: h * 0.03),

                      Text(
                        'Please check back the\nnext time you\'re here\nfor a restock!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: scale * 0.052,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),

                      const Spacer(),
                    ],
                  ),
                );
              },
            ),
          ),

          // Invisible admin entry — top-left 60x60 area, 5 taps within 2s.
          // Mirrors the idle screen's hidden gesture so the operator can
          // still reach the admin panel while this overlay is up.
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
        ],
      ),
    );
  }
}

/// Big "IT'S A HIT!" headline.
///
/// Roboto's heaviest weight (w900) still reads thinner than the condensed
/// display type in the brand mockup, so we fake a heavier weight by painting
/// a stroked copy of the glyphs over the filled text — the stroke thickens
/// every edge. Combined with tight (negative) tracking this matches the
/// mockup's chunky, packed look. FittedBox guards against horizontal overflow
/// on the narrow dev preview.
class _HitHeadline extends StatelessWidget {
  final double scale;
  const _HitHeadline({required this.scale});

  static const _text = "IT'S A HIT!";

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: scale * 0.165,
      fontWeight: FontWeight.w900,
      letterSpacing: scale * -0.004,
      height: 1.0,
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Filled glyphs.
          Text(
            _text,
            textAlign: TextAlign.center,
            style: base.copyWith(color: Colors.white),
          ),
          // Stroke on top thickens the edges → heavier than w900.
          Text(
            _text,
            textAlign: TextAlign.center,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = scale * 0.007
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Text fallback if the co-branded lockup asset is missing, so the screen
/// still reads as intentional Chevrolet / Detroit Tigers branding.
class _LogoFallback extends StatelessWidget {
  final double scale;
  const _LogoFallback({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CHEVROLET',
          style: TextStyle(
            color: Colors.white,
            fontSize: scale * 0.08,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        SizedBox(height: scale * 0.02),
        Text(
          'Official Vehicle of the Detroit Tigers™',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: scale * 0.032,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
