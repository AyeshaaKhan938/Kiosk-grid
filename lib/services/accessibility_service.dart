import 'package:flutter/semantics.dart';

/// Helper para anunciar cambios de estado a lectores de pantalla.
/// Cumple con ADA / WCAG 2.1 Success Criterion 4.1.3 (Status Messages).
class AccessibilityService {
  static void announce(String message) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  static void announceError(String error) {
    SemanticsService.announce('Error: $error', TextDirection.ltr);
  }

  static void announceNavigation(String screenName) {
    SemanticsService.announce('Navigated to $screenName', TextDirection.ltr);
  }
}
