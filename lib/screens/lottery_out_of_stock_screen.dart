import 'package:flutter/material.dart';

/// Fullscreen overlay when lottery prize stock reaches zero.
class LotteryOutOfStockScreen extends StatelessWidget {
  const LotteryOutOfStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Image.asset(
                'assets/images/chevrolet_tigers_lockup.png',
                fit: BoxFit.contain,
                width: MediaQuery.sizeOf(context).width * 0.92,
              ),
              const Spacer(flex: 2),
              const Text(
                "IT'S A HIT!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 36),
              Text(
                'Our prizes were so popular that we\'ve run out.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Please check back the next time you\'re here for a restock!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
