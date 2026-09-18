import 'package:flutter/material.dart';

import '../../models/demo_guide_step.dart';
import '../../services/app_config.dart';
import '../../services/demo_navigation.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_page_scaffold.dart';
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
    final coil = AppConfig.isCoilMachine;
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
      backgroundColor: AdminColors.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Guided setup'),
            Text(
              'Step ${_index + 1} of ${_steps.length}',
              style: const TextStyle(
                color: AdminColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminTheme.withLightTheme(
                  child: const DemoModeScreen(),
                ),
              ),
            ),
            child: const Text('Video'),
          ),
          TextButton(
            onPressed: _exitDemo,
            child: const Text('Exit'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: List.generate(_steps.length, (i) {
                final done = i < _index;
                final active = i == _index;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                      right: i == _steps.length - 1 ? 0 : 5,
                    ),
                    height: 5,
                    decoration: BoxDecoration(
                      color: active || done
                          ? AdminColors.accent
                          : AdminColors.border,
                      borderRadius: BorderRadius.circular(3),
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
          AdminBottomChrome(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _index > 0 ? () => _go(-1) : null,
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 10),
                  if (step.destination != DemoGuideDestination.none) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => openDemoGuideDestination(
                          context,
                          step.destination,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Try'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: step.destination != DemoGuideDestination.none ? 1 : 2,
                    child: FilledButton(
                      onPressed: _index < _steps.length - 1
                          ? () => _go(1)
                          : () => Navigator.pop(context),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: AdminSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AdminColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    step.icon,
                    color: AdminColors.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    step.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              step.summary,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AdminColors.textSecondary,
                  ),
            ),
            if (step.coilOnlyNote) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AdminColors.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AdminColors.warning,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Coil machines only — skip lift platform calibration '
                        'on spiral coil units.',
                        style: TextStyle(
                          color: Color(0xFF7A4E00),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            const AdminSectionLabel('Checklist'),
            const SizedBox(height: 4),
            ...step.bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AdminColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AdminColors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b,
                        style: const TextStyle(
                          color: AdminColors.textPrimary,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
