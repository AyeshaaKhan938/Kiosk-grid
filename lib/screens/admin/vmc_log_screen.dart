import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_config.dart';
import '../../services/vending_machine_service.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_page_scaffold.dart';

class VmcLogScreen extends StatefulWidget {
  const VmcLogScreen({super.key});

  @override
  State<VmcLogScreen> createState() => _VmcLogScreenState();
}

class _VmcLogScreenState extends State<VmcLogScreen> {
  bool _loading = false;
  String _status = 'Tap Fetch log to download diagnostics from the VMC.';
  String _logText = '';

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _status = 'Sending CMD 0x03 at 9600 baud, then reading log at 115200…';
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

  Future<void> _copyLog() async {
    if (_logText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _logText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('VMC log copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'VMC log',
      subtitle: AppConfig.ttyPath,
      leading: AdminPageScaffold.backLeading(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status,
                  style: const TextStyle(
                    color: AdminColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Request at 9600 · log stream at 115200',
                  style: TextStyle(
                    color: AdminColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _fetch,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_loading ? 'Fetching…' : 'Fetch log'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _logText.isEmpty ? null : _copyLog,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.accent,
                  side: const BorderSide(color: AdminColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: AdminSurfaceCard(
              padding: const EdgeInsets.all(12),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AdminColors.accent,
                      ),
                    )
                  : Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _logText.isEmpty
                              ? 'No VMC log loaded yet.'
                              : _logText,
                          style: TextStyle(
                            color: _logText.isEmpty
                                ? AdminColors.textMuted
                                : AdminColors.textPrimary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
