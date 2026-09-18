import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vmfs_brand_colors.dart';

/// Light, cloud-aligned palette for operator / admin / demo surfaces.
abstract final class AdminColors {
  static const Color canvas = VmfsBrandColors.cloudSurface;

  static const Color card = Colors.white;

  static const Color fieldFill = VmfsBrandColors.cloudSurfaceAlt;

  static const Color border = VmfsBrandColors.cloudBorder;

  static const Color textPrimary = Color(0xFF1A2B3C);

  static const Color textSecondary = Color(0xFF5A6B7C);

  static const Color textMuted = Color(0xFF8A9AAB);

  static const Color accent = VmfsBrandColors.cloudPrimary;

  static const Color success = Color(0xFF2E7D32);

  static const Color warning = Color(0xFFED6C02);

  static const Color danger = Color(0xFFC62828);
}

/// Material theme for admin panel, settings, and demo / training screens.
abstract final class AdminTheme {
  static ThemeData get light {
    const textTheme = TextTheme(
      displaySmall: TextStyle(
        color: AdminColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 28,
        letterSpacing: -0.4,
      ),
      headlineSmall: TextStyle(
        color: AdminColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 22,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        color: AdminColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
      titleMedium: TextStyle(
        color: AdminColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      bodyLarge: TextStyle(
        color: AdminColors.textPrimary,
        fontSize: 16,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        color: AdminColors.textSecondary,
        fontSize: 14,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        color: AdminColors.textMuted,
        fontSize: 12,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        color: AdminColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AdminColors.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AdminColors.accent,
        brightness: Brightness.light,
        primary: AdminColors.accent,
        surface: AdminColors.card,
        onSurface: AdminColors.textPrimary,
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AdminColors.card,
        foregroundColor: AdminColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: AdminColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AdminColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AdminColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AdminColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: AdminColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: AdminColors.textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AdminColors.border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AdminColors.accent,
        textColor: AdminColors.textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AdminColors.fieldFill,
        selectedColor: AdminColors.accent.withValues(alpha: 0.12),
        labelStyle: const TextStyle(
          color: AdminColors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        side: const BorderSide(color: AdminColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdminColors.fieldFill,
        hintStyle: const TextStyle(color: AdminColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: AdminColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AdminColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AdminColors.accent,
          side: const BorderSide(color: AdminColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AdminColors.accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AdminColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AdminColors.card,
        elevation: 0,
        height: 72,
        indicatorColor: AdminColors.accent.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AdminColors.accent : AdminColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? AdminColors.accent : AdminColors.textMuted,
          );
        }),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AdminColors.card,
        selectedItemColor: AdminColors.accent,
        unselectedItemColor: AdminColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
    );
  }

  static Widget withLightTheme({required Widget child}) =>
      Theme(data: light, child: child);
}
