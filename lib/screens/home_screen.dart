import 'package:flutter/material.dart';
import '../models/machine_slot.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Slot del producto que el usuario seleccionó en el browser.
  final MachineSlot? slot;

  const HomeScreen({super.key, this.slot});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _requestPrice() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final result = await ApiService.claimPrice();
      if (!mounted) return;
      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => ResultScreen(
            price: result['price'] ?? '0.00',
            message: result['message'] ?? 'Congratulations!',
            lineNumber: int.tryParse(result['lineNumber'] ?? ''),
            machineNo: result['machineNo'] ?? '',
            lotteryCode: result['lotteryCode'] ?? '',
            slot: widget.slot,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final noCoupons = e.toString().contains('unavailable');
      _showErrorDialog(noCoupons: noCoupons);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog({bool noCoupons = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              noCoupons ? Icons.inventory_2_outlined : Icons.wifi_off,
              color: const Color(0xFF007ACC),
            ),
            const SizedBox(width: 8),
            Text(
              noCoupons ? 'No coupons' : 'No connection',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Text(
          noCoupons
              ? 'There are no coupons available right now. Please contact a representative.'
              : 'Could not connect to the server. Check the connection and try again.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF007ACC))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Subtle gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0xFF0A1628),
                  Colors.black,
                ],
              ),
            ),
          ),

          // Decorative background particles
          ...List.generate(6, (i) => _buildDecorativeCircle(i, size)),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Company logo / name
                _buildLogo(),
                const SizedBox(height: 16),

                // Subtitle
                Text(
                  widget.slot != null
                      ? widget.slot!.productName
                      : 'Your special price is waiting',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 20,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 60),

                // Main button
                _isLoading ? _buildLoadingIndicator() : _buildMainButton(),

                const SizedBox(height: 40),

                // Touch instruction
                if (!_isLoading)
                  const Text(
                    'Tap the button to reveal your price',
                    style: TextStyle(
                      color: Colors.white30,
                      fontSize: 15,
                    ),
                  ),
              ],
            ),
          ),

          // Version / footer
          const Positioned(
            bottom: 16,
            right: 24,
            child: Text(
              'VMFS USA © 2026',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF007ACC),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF007ACC).withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'VMFS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'VMFS USA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildMainButton() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: GestureDetector(
        onTap: _requestPrice,
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF1A9FE0), Color(0xFF007ACC)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF007ACC).withValues(alpha: 0.6),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.monetization_on_rounded, color: Colors.white, size: 70),
              SizedBox(height: 12),
              Text(
                'GET YOUR\nPRICE!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Column(
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            color: Color(0xFF007ACC),
            strokeWidth: 6,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Generating your price...',
          style: TextStyle(color: Colors.white70, fontSize: 18),
        ),
      ],
    );
  }

  Widget _buildDecorativeCircle(int index, Size size) {
    final positions = [
      const Offset(0.05, 0.1),
      const Offset(0.9, 0.05),
      const Offset(0.15, 0.85),
      const Offset(0.85, 0.8),
      const Offset(0.5, 0.02),
      const Offset(0.02, 0.5),
    ];
    final sizes = [80.0, 120.0, 60.0, 100.0, 70.0, 90.0];

    return Positioned(
      left: size.width * positions[index].dx,
      top: size.height * positions[index].dy,
      child: Container(
        width: sizes[index],
        height: sizes[index],
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF007ACC).withValues(alpha: 0.05),
          border: Border.all(
            color: const Color(0xFF007ACC).withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
    );
  }
}
