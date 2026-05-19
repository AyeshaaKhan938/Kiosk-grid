import 'package:flutter/material.dart';

/// Configuración de accesibilidad — singleton que notifica cambios a toda la app.
class AccessibilitySettings extends ChangeNotifier {
  static final AccessibilitySettings instance = AccessibilitySettings._();
  AccessibilitySettings._();

  // ── Estado ──────────────────────────────────────────────────────────────────

  double _textScale   = 1.0;   // 1.0 | 1.25 | 1.5
  bool   _highContrast = false;

  double get textScale    => _textScale;
  bool   get highContrast => _highContrast;

  // ── Acciones ─────────────────────────────────────────────────────────────────

  void setTextScale(double scale) {
    if (_textScale == scale) return;
    _textScale = scale;
    notifyListeners();
  }

  void toggleHighContrast() {
    _highContrast = !_highContrast;
    notifyListeners();
  }

  // ── Tema dinámico ─────────────────────────────────────────────────────────────

  ThemeData buildTheme() {
    if (_highContrast) {
      return ThemeData(
        colorScheme: const ColorScheme.dark(
          primary:                  Color(0xFFFFD700),
          onPrimary:                Colors.black,
          surface:                  Color(0xFF121212),
          onSurface:                Colors.white,
          surfaceContainerHighest:  Color(0xFF2A2A2A),
          secondary:                Color(0xFFFFD700),
          onSecondary:              Colors.black,
          error:                    Colors.redAccent,
          onError:                  Colors.white,
        ),
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Roboto',
        dividerColor: const Color(0xFF444444),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFFD700),
            side: const BorderSide(color: Color(0xFFFFD700)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
    }
    return ThemeData(
      colorScheme: const ColorScheme.light(
        primary:                  Color(0xFF007ACC),
        onPrimary:                Colors.white,
        surface:                  Colors.white,
        onSurface:                Colors.black87,
        surfaceContainerHighest:  Color(0xFFF5F7FA),
        secondary:                Color(0xFF007ACC),
        onSecondary:              Colors.white,
        error:                    Colors.redAccent,
        onError:                  Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      fontFamily: 'Roboto',
      dividerColor: Colors.black12,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF007ACC),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black54,
          side: const BorderSide(color: Colors.black26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
