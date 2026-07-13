import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/age_verification_service.dart';
import 'product_browser_screen.dart';

/// Age verification gate — customer scans the dynamic QR with their phone,
/// uploads a government ID on the cloud link, and the kiosk polls vms-cloud
/// until the third-party verifier confirms they are 18+.
class AgeVerificationScreen extends StatefulWidget {
  const AgeVerificationScreen({super.key});

  @override
  State<AgeVerificationScreen> createState() => _AgeVerificationScreenState();
}

enum _Phase { loading, waiting, verified, rejected, error }

class _AgeVerificationScreenState extends State<AgeVerificationScreen> {
  _Phase _phase = _Phase.loading;
  String _errorMsg = '';
  String _statusMsg = 'Starting verification…';
  AgeVerificationSession? _session;
  Timer? _pollTimer;

  static const _pollInterval = Duration(seconds: 2);
  static const _sessionTimeout = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSession() async {
    setState(() {
      _phase = _Phase.loading;
      _errorMsg = '';
      _statusMsg = 'Starting verification…';
      _session = null;
    });
    _pollTimer?.cancel();

    try {
      final session = await AgeVerificationService.createSession();
      if (!mounted) return;

      setState(() {
        _session = session;
        _phase = _Phase.waiting;
        _statusMsg = 'Scan the QR code with your phone';
      });

      _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
      // Auto-expire the screen if the customer walks away.
      Future.delayed(_sessionTimeout, () {
        if (mounted && _phase == _Phase.waiting) {
          setState(() {
            _phase = _Phase.error;
            _errorMsg = 'Verification timed out. Please try again.';
          });
          _pollTimer?.cancel();
        }
      });
    } on AgeVerificationException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMsg = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMsg = 'Connection error. Check the network.';
        });
      }
    }
  }

  Future<void> _pollOnce() async {
    final session = _session;
    if (session == null || _phase != _Phase.waiting) return;

    try {
      final result = await AgeVerificationService.pollStatus(session.sessionId);
      if (!mounted) return;

      switch (result.status) {
        case AgeVerificationStatus.pending:
          setState(() => _statusMsg = 'Scan the QR code with your phone');
        case AgeVerificationStatus.uploaded:
        case AgeVerificationStatus.processing:
          setState(() => _statusMsg = 'Verifying your ID…');
        case AgeVerificationStatus.verified:
          if (result.ageVerified) {
            _pollTimer?.cancel();
            setState(() {
              _phase = _Phase.verified;
              _statusMsg = 'Age verified!';
            });
            await Future.delayed(const Duration(milliseconds: 800));
            if (!mounted) return;
            _goToProducts(session.sessionId);
          } else {
            _pollTimer?.cancel();
            setState(() {
              _phase = _Phase.rejected;
              _errorMsg = result.message ?? 'You must be 18 or older.';
            });
          }
        case AgeVerificationStatus.rejected:
          _pollTimer?.cancel();
          setState(() {
            _phase = _Phase.rejected;
            _errorMsg = result.message ?? 'Verification failed. Must be 18+.';
          });
        case AgeVerificationStatus.expired:
          _pollTimer?.cancel();
          setState(() {
            _phase = _Phase.error;
            _errorMsg = result.message ?? 'Session expired.';
          });
        case AgeVerificationStatus.unknown:
          break;
      }
    } catch (_) {
      // Transient network blip — keep polling.
    }
  }

  void _goToProducts(String sessionId) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => ProductBrowserScreen(
          ageVerificationSessionId: sessionId,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
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
            final scale = math.min(w, h / 1.8);

            return Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.06,
                    vertical: h * 0.03,
                  ),
                  child: Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: scale * 0.12),
                        child: Image.asset(
                          'assets/images/chevrolet_header_logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      SizedBox(height: scale * 0.04),
                      Text(
                        'AGE VERIFICATION',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: scale * 0.065,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: scale * 0.015),
                      Text(
                        'Must be 18 or older to participate',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: scale * 0.032,
                        ),
                      ),
                      SizedBox(height: scale * 0.05),
                      Expanded(
                        child: _buildBody(scale),
                      ),
                      SizedBox(height: scale * 0.03),
                      _buildInstructions(scale),
                    ],
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
    );
  }

  Widget _buildBody(double scale) {
    switch (_phase) {
      case _Phase.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: scale * 0.08,
                height: scale * 0.08,
                child: const CircularProgressIndicator(
                  color: Color(0xFF007ACC),
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: scale * 0.03),
              Text(
                _statusMsg,
                style: TextStyle(color: Colors.white70, fontSize: scale * 0.035),
              ),
            ],
          ),
        );

      case _Phase.waiting:
      case _Phase.verified:
        final url = _session?.verifyUrl ?? '';
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(scale * 0.025),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: scale * 0.55,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            SizedBox(height: scale * 0.04),
            if (_phase == _Phase.verified)
              Icon(Icons.check_circle_rounded,
                  color: Colors.greenAccent, size: scale * 0.1)
            else
              SizedBox(
                width: scale * 0.05,
                height: scale * 0.05,
                child: const CircularProgressIndicator(
                  color: Colors.white54,
                  strokeWidth: 2,
                ),
              ),
            SizedBox(height: scale * 0.02),
            Text(
              _statusMsg,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _phase == _Phase.verified
                    ? Colors.greenAccent
                    : Colors.white70,
                fontSize: scale * 0.038,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case _Phase.rejected:
      case _Phase.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: scale * 0.12),
              SizedBox(height: scale * 0.03),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: scale * 0.05),
                child: Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: scale * 0.04,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: scale * 0.05),
              ElevatedButton(
                onPressed: _startSession,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007ACC),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: scale * 0.08,
                    vertical: scale * 0.025,
                  ),
                ),
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: scale * 0.04,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildInstructions(double scale) {
    if (_phase == _Phase.error || _phase == _Phase.rejected) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        _InstructionStep(
          num: '1',
          text: 'Scan the QR code with your phone camera',
          scale: scale,
        ),
        SizedBox(height: scale * 0.012),
        _InstructionStep(
          num: '2',
          text: 'Take a photo of your ID or passport',
          scale: scale,
        ),
        SizedBox(height: scale * 0.012),
        _InstructionStep(
          num: '3',
          text: 'Wait here — verification is automatic',
          scale: scale,
        ),
      ],
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String num;
  final String text;
  final double scale;

  const _InstructionStep({
    required this.num,
    required this.text,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: scale * 0.06,
          height: scale * 0.06,
          decoration: BoxDecoration(
            color: const Color(0xFF007ACC),
            borderRadius: BorderRadius.circular(scale * 0.03),
          ),
          alignment: Alignment.center,
          child: Text(
            num,
            style: TextStyle(
              color: Colors.white,
              fontSize: scale * 0.03,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        SizedBox(width: scale * 0.025),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: scale * 0.032,
            ),
          ),
        ),
      ],
    );
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
          width: size,
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
