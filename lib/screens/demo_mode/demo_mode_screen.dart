import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/app_config.dart';
import '../../theme/admin_theme.dart';
import '../../theme/vmfs_brand_colors.dart';
import '../../widgets/admin/admin_page_scaffold.dart';
import 'demo_guide_screen.dart';

/// Demo / training hub: intro video + entry to the guided setup walkthrough.
class DemoModeScreen extends StatefulWidget {
  const DemoModeScreen({super.key});

  static Future<void> enter(BuildContext context) async {
    await AppConfig.setDemoMode(true);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AdminTheme.withLightTheme(child: const DemoModeScreen()),
      ),
    );
  }

  @override
  State<DemoModeScreen> createState() => _DemoModeScreenState();
}

class _DemoModeScreenState extends State<DemoModeScreen> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = AppConfig.demoVideoUrl;
    VideoPlayerController? ctrl;

    try {
      if (url.isNotEmpty) {
        ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      } else {
        ctrl = VideoPlayerController.asset('assets/videos/kiosk_demo.mp4');
      }
      await ctrl.initialize();
      ctrl.setLooping(true);
      await ctrl.play();
      if (!mounted) return;
      setState(() {
        _videoCtrl = ctrl;
        _videoReady = true;
      });
    } catch (e) {
      await ctrl?.dispose();
      if (!mounted) return;
      setState(() {
        _videoError = kDebugMode
            ? 'Video failed: $e\nAdd assets/videos/kiosk_demo.mp4 or set DEMO_VIDEO_URL in .env'
            : 'Intro video will appear here once your team uploads kiosk_demo.mp4 '
                'or configures DEMO_VIDEO_URL.';
      });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _exitDemo() async {
    await AppConfig.setDemoMode(false);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.canvas,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Demo mode'),
            Text(
              'Operator training',
              style: TextStyle(
                color: AdminColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _exitDemo,
            child: const Text('Exit'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            AdminSurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    decoration: const BoxDecoration(
                      gradient: VmfsBrandColors.headerGradient,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/images/vmfs-logo.jpg',
                            height: 44,
                            width: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 44,
                              width: 44,
                              color: Colors.white24,
                              child: const Icon(Icons.school_rounded,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VMFS Kiosk Grid',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Simulated dispense is ON — safe for training.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Text(
                      'Follow the guided steps to learn Wi‑Fi, cloud activation, '
                      'admin panel, products, slots, updates, and hardware setup '
                      'for this cabinet type.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AdminSurfaceCard(
              padding: const EdgeInsets.all(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: AdminColors.fieldFill,
                    child: _buildVideoArea(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminTheme.withLightTheme(
                      child: const DemoGuideScreen(initialStepIndex: 1),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Start guided machine setup'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminTheme.withLightTheme(
                      child: const DemoGuideScreen(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Browse all guide steps'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_videoReady && _videoCtrl != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoCtrl!.value.size.width,
              height: _videoCtrl!.value.size.height,
              child: VideoPlayer(_videoCtrl!),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () {
                  final c = _videoCtrl!;
                  setState(() {
                    c.value.isPlaying ? c.pause() : c.play();
                  });
                },
                icon: Icon(
                  _videoCtrl!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_videoError != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: AdminColors.textMuted,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              _videoError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AdminColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: CircularProgressIndicator(color: AdminColors.accent),
    );
  }
}
