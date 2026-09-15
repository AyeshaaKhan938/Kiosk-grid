import 'package:flutter/material.dart';

import '../services/app_config.dart';
import '../services/kiosk_cloud_service.dart';
import 'onscreen_keypad.dart';

/// One-time kiosk activation with vms-cloud (heartbeat + issue reporting).
/// Shown during setup (Backend step) and in Admin Settings for re-link.
class CloudActivationPanel extends StatefulWidget {
  const CloudActivationPanel({super.key, this.onSaved});

  final VoidCallback? onSaved;

  @override
  State<CloudActivationPanel> createState() => _CloudActivationPanelState();
}

class _CloudActivationPanelState extends State<CloudActivationPanel> {
  late final TextEditingController _codeCtrl;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() {
        _message = 'Enter the activation code from vms-cloud admin.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    final error = await KioskCloudService.instance.activate(
      activationCode: code,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;
      if (error == null) {
        _message = 'Activated — machine issue reporting is now enabled.';
        _isError = false;
        _codeCtrl.clear();
      } else {
        _message = error;
        _isError = true;
      }
    });
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final activated = AppConfig.hasDeviceToken;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: activated
              ? const Color(0xFF22C55E).withValues(alpha: 0.5)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              activated ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: activated ? const Color(0xFF22C55E) : Colors.orange,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                activated
                    ? 'Cloud device activated (${AppConfig.deviceToken.substring(0, 8)}…)'
                    : 'Not activated — faults stay local only',
                style: TextStyle(
                  color: activated ? Colors.white70 : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
          if (!activated) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  readOnly: true,
                  showCursor: true,
                  enableInteractiveSelection: false,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'Activation code',
                    hintStyle:
                        const TextStyle(color: Colors.white24, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF060E18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onTap: () => showKeypad(
                    context,
                    controller: _codeCtrl,
                    mode: KeypadMode.alphanumeric,
                    title: 'ACTIVATION CODE',
                    hint: 'From vms-cloud → Machines → Activate kiosk',
                    onCommitted: (_) => setState(() => _message = null),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _busy ? null : _activate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Activate',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ]),
          ],
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: TextStyle(
                color: _isError ? Colors.redAccent : const Color(0xFF22C55E),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'vms-cloud → Machines → select machine → Generate activation code.\n'
            'Reports: dispense failures, board offline, elevator/pusher faults.',
            style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}
