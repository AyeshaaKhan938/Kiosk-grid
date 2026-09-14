import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/app_config.dart';
import 'demo_guide_screen.dart';

/// Demo / training hub: intro video + entry to the guided setup walkthrough.
class DemoModeScreen extends StatefulWidget {
  const DemoModeScreen({super.key});

  static Future<void> enter(BuildContext context) async {
    await AppConfig.setDemoMode(true);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DemoModeScreen()),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        foregroundColor: Colors.white,
        title: const Text('Demo mode'),
        actions: [
          TextButton(
            onPressed: _exitDemo,
            child: const Text('Exit demo'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'VMFS Kiosk Grid — operator training',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Simulated dispense is ON. Follow the guided steps to learn Wi‑Fi, cloud, '
              'admin panel, products, slots, updates, coil setup, and fault reset.',
              style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: const Color(0xFF0A1628),
                  child: _buildVideoArea(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DemoGuideScreen(initialStepIndex: 1),
                  ),
                );
              },
              icon: const Icon(Icons.menu_book_rounded),
              label: const Text('Start guided machine setup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007ACC),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DemoGuideScreen()),
                );
              },
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Browse all guide steps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
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
          VideoPlayer(_videoCtrl!),
          Positioned(
            bottom: 8,
            right: 8,
            child: IconButton(
              onPressed: () {
                final c = _videoCtrl!;
                setState(() {
                  c.value.isPlaying ? c.pause() : c.play();
                });
              },
              icon: Icon(
                _videoCtrl!.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: Colors.white.withValues(alpha: 0.9),
                size: 44,
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
            const Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(
              _videoError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF007ACC)),
    );
  }
}
