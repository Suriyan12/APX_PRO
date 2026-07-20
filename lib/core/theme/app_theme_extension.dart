import 'package:flutter/material.dart';

class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.background,
    required this.surface,
    required this.surfaceOverlay,
    required this.primary,
    required this.primaryGlow,
    required this.secondary,
    required this.accentPink,
    required this.success,
    required this.warning,
    required this.error,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderGlow,
    required this.glassTint,
    required this.glassBorder,
    required this.glassBorderBottom,
    required this.glassAppBarTint,
    required this.glassNavTint,
    required this.glassDialogTint,
    required this.glassDialogBorder,
    required this.glassTextFieldFill,
    required this.orb1,
    required this.orb2,
    required this.orb3,
    required this.orb4,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceOverlay;
  final Color primary;
  final Color primaryGlow;
  final Color secondary;
  final Color accentPink;
  final Color success;
  final Color warning;
  final Color error;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderGlow;
  final Color glassTint;
  final Color glassBorder;
  final Color glassBorderBottom;
  final Color glassAppBarTint;
  final Color glassNavTint;
  final Color glassDialogTint;
  final Color glassDialogBorder;
  final Color glassTextFieldFill;
  final Color orb1;
  final Color orb2;
  final Color orb3;
  final Color orb4;
  final bool isDark;

  @override
  AppThemeExtension copyWith({
    Color? background,
    Color? surface,
    Color? surfaceOverlay,
    Color? primary,
    Color? primaryGlow,
    Color? secondary,
    Color? accentPink,
    Color? success,
    Color? warning,
    Color? error,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? borderGlow,
    Color? glassTint,
    Color? glassBorder,
    Color? glassBorderBottom,
    Color? glassAppBarTint,
    Color? glassNavTint,
    Color? glassDialogTint,
    Color? glassDialogBorder,
    Color? glassTextFieldFill,
    Color? orb1,
    Color? orb2,
    Color? orb3,
    Color? orb4,
    bool? isDark,
  }) {
    return AppThemeExtension(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      primary: primary ?? this.primary,
      primaryGlow: primaryGlow ?? this.primaryGlow,
      secondary: secondary ?? this.secondary,
      accentPink: accentPink ?? this.accentPink,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      borderGlow: borderGlow ?? this.borderGlow,
      glassTint: glassTint ?? this.glassTint,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBorderBottom: glassBorderBottom ?? this.glassBorderBottom,
      glassAppBarTint: glassAppBarTint ?? this.glassAppBarTint,
      glassNavTint: glassNavTint ?? this.glassNavTint,
      glassDialogTint: glassDialogTint ?? this.glassDialogTint,
      glassDialogBorder: glassDialogBorder ?? this.glassDialogBorder,
      glassTextFieldFill: glassTextFieldFill ?? this.glassTextFieldFill,
      orb1: orb1 ?? this.orb1,
      orb2: orb2 ?? this.orb2,
      orb3: orb3 ?? this.orb3,
      orb4: orb4 ?? this.orb4,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppThemeExtension lerp(AppThemeExtension? other, double t) {
    if (other == null) return this;
    return AppThemeExtension(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryGlow: Color.lerp(primaryGlow, other.primaryGlow, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      accentPink: Color.lerp(accentPink, other.accentPink, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderGlow: Color.lerp(borderGlow, other.borderGlow, t)!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBorderBottom: Color.lerp(glassBorderBottom, other.glassBorderBottom, t)!,
      glassAppBarTint: Color.lerp(glassAppBarTint, other.glassAppBarTint, t)!,
      glassNavTint: Color.lerp(glassNavTint, other.glassNavTint, t)!,
      glassDialogTint: Color.lerp(glassDialogTint, other.glassDialogTint, t)!,
      glassDialogBorder: Color.lerp(glassDialogBorder, other.glassDialogBorder, t)!,
      glassTextFieldFill: Color.lerp(glassTextFieldFill, other.glassTextFieldFill, t)!,
      orb1: Color.lerp(orb1, other.orb1, t)!,
      orb2: Color.lerp(orb2, other.orb2, t)!,
      orb3: Color.lerp(orb3, other.orb3, t)!,
      orb4: Color.lerp(orb4, other.orb4, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension BuildContextThemeX on BuildContext {
  AppThemeExtension get ext =>
      Theme.of(this).extension<AppThemeExtension>()!;
}
