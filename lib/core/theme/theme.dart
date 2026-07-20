import 'package:flutter/material.dart';
import 'package:apx_pro/core/theme/dark_theme.dart';
import 'package:apx_pro/core/theme/light_theme.dart';

enum AppThemeMode { system, light, dark }

enum AccentColor { cyan, blue, purple }

class AppTheme {
  static const _darkAccents = {
    AccentColor.cyan:   Color(0xFF00F2FE),
    AccentColor.blue:   Color(0xFF4FC3F7),
    AccentColor.purple: Color(0xFFCE93D8),
  };

  static const _lightAccents = {
    AccentColor.cyan:   Color(0xFF00B4D8),
    AccentColor.blue:   Color(0xFF0288D1),
    AccentColor.purple: Color(0xFF7B1FA2),
  };

  static ThemeData dark(AccentColor accent) =>
      buildDarkTheme(_darkAccents[accent]!);

  static ThemeData light(AccentColor accent) =>
      buildLightTheme(_lightAccents[accent]!);
}
