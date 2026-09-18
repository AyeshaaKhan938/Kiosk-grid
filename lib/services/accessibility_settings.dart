import 'package:flutter/material.dart';

import '../theme/vmfs_brand_colors.dart';

/// Configuración de accesibilidad — singleton que notifica cambios a toda la app.
class AccessibilitySettings extends ChangeNotifier {
  static final AccessibilitySettings instance = AccessibilitySettings._();
  AccessibilitySettings._();

  double _textScale   = 1.0;
  bool   _highContrast = false;

  double get textScale    => _textScale;
  bool   get highContrast => _highContrast;

  void setTextScale(double scale) {
    if (_textScale == scale) return;
    _textScale = scale;
    notifyListeners();
  }

  void toggleHighContrast() {
    _highContrast = !_highContrast;
    notifyListeners();
  }

  ThemeData buildTheme() {
    if (_highContrast) {
      return ThemeData(
        useMaterial3: true,
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

    const primary = VmfsBrandColors.cloudPrimary;
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary:                  primary,
        onPrimary:                Colors.white,
        surface:                  Colors.white,
        onSurface:                Color(0xFF0F172A),
        surfaceContainerHighest:  VmfsBrandColors.cloudSurface,
        secondary:                VmfsBrandColors.cloudPrimaryDark,
        onSecondary:              Colors.white,
        error:                    Color(0xFFDC2626),
        onError:                  Colors.white,
        outline:                  VmfsBrandColors.cloudBorder,
      ),
      scaffoldBackgroundColor: VmfsBrandColors.cloudSurface,
      fontFamily: 'Roboto',
      dividerColor: VmfsBrandColors.cloudBorder,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: VmfsBrandColors.cloudBorder),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: VmfsBrandColors.cloudBorder),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
