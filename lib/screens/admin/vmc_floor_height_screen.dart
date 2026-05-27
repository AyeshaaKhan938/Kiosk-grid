import 'package:flutter/material.dart';

import '../../services/app_config.dart';
import '../../services/vending_machine_service.dart';
import '../../widgets/onscreen_keypad.dart';

class VmcFloorHeightScreen extends StatefulWidget {
  const VmcFloorHeightScreen({super.key});

  @override
  State<VmcFloorHeightScreen> createState() => _VmcFloorHeightScreenState();
}

class _VmcFloorHeightScreenState extends State<VmcFloorHeightScreen> {
  bool _loading = false;
  bool _autoRunning = false;
  String _status = 'Tap Refresh to read lift floor heights from the VMC.';
  String? _rawHex;
  List<int> _heights = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = 'Reading CMD 0x20 on ${AppConfig.ttyPath}...';
    });

    final result = await VendingMachineService.queryFloorHeights();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _heights = result.heights;
      _rawHex = result.rawHex;
      _status = result.success
          ? 'Read ${result.heights.length} floor heights from the VMC.'
          : result.errorMessage ?? 'Failed to read floor heights.';
    });
  }

  Future<void> _runAutoHeight() async {
    setState(() {
      _autoRunning = true;
      _status = 'Sending auto-height CMD 0x21. The lift may move now...';
    });

    final result = await VendingMachineService.calibrateLiftViaGate();
    if (!mounted) return;
    setState(() {
      _autoRunning = false;
      _status = result.status == DispenseStatus.success
          ? 'Auto-height command completed. Refresh to read saved values.'
          : result.errorMessage ?? 'Auto-height failed.';
    });
  }

  Future<void> _editHeight(int floor, int currentHeight) async {
    final ctrl = TextEditingController(text: currentHeight.toString());
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Set Floor $floor Height',
          style: const TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: TextField(
          controller: ctrl,
          readOnly: true,
          showCursor: true,
          enableInteractiveSelection: false,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22),
          decoration: InputDecoration(
            hintText: 'Height',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF060E18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
          ),
          onTap: () => showKeypad(
            ctx,
            controller: ctrl,
            mode: KeypadMode.numeric,
            maxLength: 5,
            title: 'FLOOR HEIGHT',
            hint: '0 - 65535',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(ctrl.text.trim());
              if (value == null || value < 0 || value > 65535) return;
              Navigator.pop(ctx, value);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E24AA),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (picked == null || !mounted) return;
    setState(() => _status = 'Sending CMD 0x21 for floor $floor...');
    final result = await VendingMachineService.setFloorHeight(
      floor: floor,
      height: picked,
    );
    if (!mounted) return;
    if (result.status == DispenseStatus.success) {
      await _refresh();
    } else {
      setState(() => _status = result.errorMessage ?? 'Set height failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _autoRunning;
    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A2B),
        foregroundColor: Colors.white,
        title: const Text('Lift Floor Heights'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _InfoPanel(status: _status, rawHex: _rawHex),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007ACC),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : _runAutoHeight,
                  icon: const Icon(Icons.vertical_align_top_rounded),
                  label: const Text('Auto Height'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8E24AA),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: Color(0xFF007ACC)),
              ),
            )
          else if (_heights.isEmpty)
            const Text(
              'No floor heights loaded.',
              style: TextStyle(color: Colors.white38),
              textAlign: TextAlign.center,
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < _heights.length; i++)
                  _FloorHeightTile(
                    floor: i + 1,
                    height: _heights[i],
                    onEdit: () => _editHeight(i + 1, _heights[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String status;
  final String? rawHex;

  const _InfoPanel({required this.status, this.rawHex});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            'Port: ${AppConfig.ttyPath} @ 9600',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          if (rawHex != null) ...[
            const SizedBox(height: 8),
            Text(
              rawHex!,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FloorHeightTile extends StatelessWidget {
  final int floor;
  final int height;
  final VoidCallback onEdit;

  const _FloorHeightTile({
    required this.floor,
    required this.height,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Material(
        color: const Color(0xFF0D1A2B),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Floor $floor',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  height.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap to edit',
                  style: TextStyle(color: Color(0xFF8E24AA), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
