import 'package:flutter/material.dart';

const Duration _forwardDuration = Duration(milliseconds: 280);
const Duration _reverseDuration = Duration(milliseconds: 240);

Route<T> kioskSlideRoute<T>({
  required Widget Function(BuildContext) builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: _forwardDuration,
    reverseTransitionDuration: _reverseDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.88, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

Route<T> kioskFadeRoute<T>({
  required Widget Function(BuildContext) builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: _reverseDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

extension KioskNavigatorContext on BuildContext {
  Future<T?> pushKioskScreen<T>(Widget screen, {bool fade = false}) {
    final route = fade
        ? kioskFadeRoute<T>(builder: (_) => screen)
        : kioskSlideRoute<T>(builder: (_) => screen);
    return Navigator.of(this).push<T>(route);
  }
}
