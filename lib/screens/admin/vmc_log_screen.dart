import 'package:flutter/material.dart';

import '../../services/app_config.dart';
import '../../services/vending_machine_service.dart';

class VmcLogScreen extends StatefulWidget {
  const VmcLogScreen({super.key});

  @override
  State<VmcLogScreen> createState() => _VmcLogScreenState();
}

class _VmcLogScreenState extends State<VmcLogScreen> {
  bool _loading = false;
  String _status = 'Tap Fetch Log to request the VMC log.';
  String _logText = '';

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _status = 'Sending CMD 0x03 at 9600, then reading log at 115200...';
      _logText = '';
    });

    final result = await VendingMachineService.fetchVmcLog();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _logText = result.text;
      _status = result.success
          ? 'VMC log transfer completed.'
          : result.errorMessage ?? 'VMC log transfer failed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A2B),
        foregroundColor: Colors.white,
        title: const Text('VMC Log'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A2B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_status, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Text(
                    'Port: ${AppConfig.ttyPath} | request 9600, log stream 115200',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _loading ? null : _fetch,
              icon: const Icon(Icons.article_rounded),
              label: Text(_loading ? 'Fetching...' : 'Fetch Log'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF02070D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: _loading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF00BCD4)),
                      )
                    : Scrollbar(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _logText.isEmpty ? 'No VMC log loaded.' : _logText,
                            style: TextStyle(
                              color: _logText.isEmpty
                                  ? Colors.white30
                                  : Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace',
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
