import 'package:flutter/material.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';

// Light-mode fixed palette
class _Light {
  static const Color background = Color(0xFFEFF5F8);
  static const Color surface = Color(0xFFFDFEFF);
  static const Color surfaceOverlay = Color(0xD8FFFFFF);
  static const Color secondary = Color(0xFF5E3AD4);
  static const Color accentPink = Color(0xFFD0184B);
  static const Color success = Color(0xFF008060);
  static const Color warning = Color(0xFF9A6700);
  static const Color error = Color(0xFFB42318);
  static const Color textPrimary = Color(0xFF182230);
  static const Color textSecondary = Color(0xFF475467);
  static const Color textMuted = Color(0xFF667085);
  static const Color border = Color(0x33233242);
}

AppThemeExtension buildLightExtension(Color primary) {
  return AppThemeExtension(
    background: _Light.background,
    surface: _Light.surface,
    surfaceOverlay: _Light.surfaceOverlay,
    primary: primary,
    primaryGlow: primary.withValues(alpha: 0.22),
    secondary: _Light.secondary,
    accentPink: _Light.accentPink,
    success: _Light.success,
    warning: _Light.warning,
    error: _Light.error,
    textPrimary: _Light.textPrimary,
    textSecondary: _Light.textSecondary,
    textMuted: _Light.textMuted,
    border: _Light.border,
    borderGlow: primary.withValues(alpha: 0.35),
    glassTint: const Color(0xDCFFFFFF),
    glassBorder: const Color(0x3834495E),
    glassBorderBottom: const Color(0x2634495E),
    glassAppBarTint: const Color(0xEFFFFFFF),
    glassNavTint: const Color(0xE6FFFFFF),
    glassDialogTint: const Color(0xF5FFFFFF),
    glassDialogBorder: const Color(0x3034495E),
    glassTextFieldFill: const Color(0xBFFFFFFF),
    orb1: primary.withValues(alpha: 0.16),
    orb2: const Color(0x185E3AD4),
    orb3: const Color(0x12D0184B),
    orb4: const Color(0x100087A3),
    isDark: false,
  );
}

ThemeData buildLightTheme(Color primary) {
  final ext = buildLightExtension(primary);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: _Light.background,
    extensions: [ext],
    colorScheme: ColorScheme.light(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: _Light.secondary,
      onSecondary: Colors.white,
      tertiary: _Light.accentPink,
      surface: _Light.surface,
      onSurface: _Light.textPrimary,
      error: _Light.error,
      onError: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _Light.background,
      elevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: _Light.textPrimary),
      titleTextStyle: const TextStyle(
        color: _Light.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: _Light.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _Light.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _Light.surfaceOverlay,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      labelStyle: const TextStyle(color: _Light.textSecondary),
      hintStyle: const TextStyle(color: _Light.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _Light.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _Light.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _Light.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _Light.error, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _Light.textPrimary,
        side: const BorderSide(color: _Light.border, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
          color: _Light.textPrimary, fontSize: 32, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(
          color: _Light.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(
          color: _Light.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: _Light.textPrimary, fontSize: 16),
      bodyMedium: TextStyle(color: _Light.textSecondary, fontSize: 14),
      labelSmall: TextStyle(
          color: _Light.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
    ),
  );
}
