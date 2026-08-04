import 'package:flutter/material.dart';

import '../utils/tap_feedback.dart';

/// Large touch target with press animation and kiosk tap sound.
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.primary = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final bool primary;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  void _handleTap() {
    if (!widget.enabled || widget.onTap == null) {
      return;
    }

    widget.onTap!();

    if (widget.primary) {
      TapFeedback.playPrimary();
    } else {
      TapFeedback.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled && widget.onTap != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.enabled && widget.onTap != null
          ? (_) => setState(() => _pressed = false)
          : null,
      onTapCancel: widget.enabled && widget.onTap != null
          ? () => setState(() => _pressed = false)
          : null,
      onTap: widget.enabled ? _handleTap : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
