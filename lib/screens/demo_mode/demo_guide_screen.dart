import 'package:flutter/material.dart';

import '../../models/demo_guide_step.dart';
import '../../services/app_config.dart';
import '../../services/demo_navigation.dart';
import 'demo_mode_screen.dart';

class DemoGuideScreen extends StatefulWidget {
  const DemoGuideScreen({super.key, this.initialStepIndex = 0});

  final int initialStepIndex;

  @override
  State<DemoGuideScreen> createState() => _DemoGuideScreenState();
}

class _DemoGuideScreenState extends State<DemoGuideScreen> {
  late final PageController _pageCtrl;
  late final List<DemoGuideStep> _steps;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final coil = AppConfig.isTcnVend || AppConfig.isReyeahUartVend;
    _steps = DemoGuideStep.allSteps(isCoilMachine: coil);
    _index = widget.initialStepIndex.clamp(0, _steps.length - 1);
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, _steps.length - 1);
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _exitDemo() async {
    await AppConfig.setDemoMode(false);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];

    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        foregroundColor: Colors.white,
        title: const Text('Guided machine setup'),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DemoModeScreen()),
            ),
            child: const Text('Video'),
          ),
          TextButton(
            onPressed: _exitDemo,
            child: const Text('Exit demo'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: List.generate(_steps.length, (i) {
                final active = i == _index;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i == _steps.length - 1 ? 0 : 6),
                    height: 4,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF007ACC)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: _steps.length,
              itemBuilder: (_, i) => _StepPage(step: _steps[i]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _index > 0 ? () => _go(-1) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                  if (step.destination != DemoGuideDestination.none)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => openDemoGuideDestination(
                          context,
                          step.destination,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Try in app'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  if (step.destination != DemoGuideDestination.none)
                    const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _index < _steps.length - 1
                          ? () => _go(1)
                          : () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007ACC),
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _index < _steps.length - 1 ? 'Next' : 'Done',
                      ),
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
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});

  final DemoGuideStep step;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF007ACC).withValues(alpha: 0.2),
                child: Icon(step.icon, color: const Color(0xFF007ACC), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            step.summary,
            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.45),
          ),
          if (step.coilOnlyNote) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF422006),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Coil machines only — skip lift platform calibration on spiral coil units.',
                      style: TextStyle(color: Color(0xFFFDE68A), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          ...step.bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(color: Color(0xFF007ACC), fontSize: 18)),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.45),
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
}
