import 'package:flutter/material.dart';

import '../services/app_config.dart';
import '../services/cooler_orchestrator_service.dart';
import 'admin_config_screen.dart';

/// Minimal headless UI for SMG-S400 AI coolers.
///
/// Customer pays on the external POS; this screen stays in the background
/// and shows only session progress. No product grid, cart, or checkout.
class CoolerShadowScreen extends StatefulWidget {
  const CoolerShadowScreen({super.key});

  @override
  State<CoolerShadowScreen> createState() => _CoolerShadowScreenState();
}

class _CoolerShadowScreenState extends State<CoolerShadowScreen> {
  final _orchestrator = CoolerOrchestratorService.instance;

  int _secretTaps = 0;
  DateTime? _lastSecretTap;

  @override
  void initState() {
    super.initState();
    _orchestrator.addListener(_onOrchestratorChanged);
    _orchestrator.start();
  }

  @override
  void dispose() {
    _orchestrator.removeListener(_onOrchestratorChanged);
    super.dispose();
  }

  void _onOrchestratorChanged() {
    if (mounted) setState(() {});
  }

  void _onSecretTap() {
    final now = DateTime.now();
    if (_lastSecretTap != null &&
        now.difference(_lastSecretTap!) > const Duration(seconds: 2)) {
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
    final phase = _orchestrator.phase;
    final busy = phase != CoolerFlowPhase.standby &&
        phase != CoolerFlowPhase.done &&
        phase != CoolerFlowPhase.error;

    return Scaffold(
      backgroundColor: const Color(0xFF050A12),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            width: 120,
            height: 120,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onSecretTap,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/vmfs-logo.jpg',
                    height: 72,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.ac_unit_rounded,
                      size: 72,
                      color: Color(0xFF007ACC),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFF007ACC),
                        ),
                      ),
                    ),
                  Text(
                    _orchestrator.statusLine,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: phase == CoolerFlowPhase.error
                          ? const Color(0xFFFF8A80)
                          : Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _subtitleForPhase(phase),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Machine ${AppConfig.machineNo}',
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitleForPhase(CoolerFlowPhase phase) {
    switch (phase) {
      case CoolerFlowPhase.standby:
        return 'Use the register to pay, then the cooler door will unlock automatically.';
      case CoolerFlowPhase.sessionActive:
        return 'Cameras are recording for inventory and billing.';
      case CoolerFlowPhase.uploading:
        return 'Sending video to VMFS cloud for review.';
      case CoolerFlowPhase.processing:
        return 'Your card may be charged after items are identified.';
      case CoolerFlowPhase.done:
        return 'You may leave the cooler area.';
      case CoolerFlowPhase.error:
        return 'If you need help, please ask staff at the register.';
    }
  }
}
