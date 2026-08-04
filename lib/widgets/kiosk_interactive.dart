import 'package:flutter/material.dart';

import '../utils/tap_feedback.dart';
import 'tap_scale.dart';

class KioskElevatedButton extends StatelessWidget {
  const KioskElevatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: onPressed == null ? null : () {},
      style: style,
      child: child,
    );

    if (onPressed == null) {
      return button;
    }

    return TapScale(onTap: onPressed, child: IgnorePointer(child: button));
  }
}

class KioskOutlinedButton extends StatelessWidget {
  const KioskOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed == null ? null : () {},
      style: style,
      child: child,
    );

    if (onPressed == null) {
      return button;
    }

    return TapScale(onTap: onPressed, child: IgnorePointer(child: button));
  }
}

class KioskTextButton extends StatelessWidget {
  const KioskTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      onPressed: onPressed == null ? null : () {},
      style: style,
      child: child,
    );

    if (onPressed == null) {
      return button;
    }

    return TapScale(onTap: onPressed, child: IgnorePointer(child: button));
  }
}

class KioskFilledButton extends StatelessWidget {
  const KioskFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  })  : icon = null,
        label = null;

  const KioskFilledButton.icon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget this.label,
    this.style,
  }) : child = null;

  final VoidCallback? onPressed;
  final Widget? child;
  final Widget? icon;
  final Widget? label;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final Widget button = icon != null
        ? FilledButton.icon(
            onPressed: onPressed == null ? null : () {},
            style: style,
            icon: icon!,
            label: label!,
          )
        : FilledButton(
            onPressed: onPressed == null ? null : () {},
            style: style,
            child: child!,
          );

    if (onPressed == null) {
      return button;
    }

    return TapScale(onTap: onPressed, primary: true, child: IgnorePointer(child: button));
  }
}

class KioskIconButton extends StatelessWidget {
  const KioskIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.padding,
    this.constraints,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) {
      return IconButton(
        onPressed: null,
        icon: icon,
        tooltip: tooltip,
        padding: padding,
        constraints: constraints,
      );
    }

    return TapScale(
      onTap: onPressed,
      child: Tooltip(
        message: tooltip ?? '',
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: constraints ?? const BoxConstraints(minWidth: 40, minHeight: 40),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

class KioskFloatingActionButton extends StatelessWidget {
  const KioskFloatingActionButton.extended({
    super.key,
    required this.onPressed,
    required Widget icon,
    required Widget label,
    this.backgroundColor,
    this.foregroundColor,
    this.heroTag,
  })  : _icon = icon,
        _label = label;

  final VoidCallback? onPressed;
  final Widget _icon;
  final Widget _label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final fab = FloatingActionButton.extended(
      onPressed: onPressed == null ? null : () {},
      icon: _icon,
      label: _label,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      heroTag: heroTag,
    );

    if (onPressed == null) {
      return fab;
    }

    return TapScale(onTap: onPressed, primary: true, child: IgnorePointer(child: fab));
  }
}

Future<void> kioskTap(VoidCallback action, {bool primary = false}) async {
  if (primary) {
    await TapFeedback.playPrimary();
  } else {
    await TapFeedback.play();
  }
  action();
}
