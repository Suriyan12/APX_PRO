import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apx_pro/core/theme/theme.dart';

// ── Persistence keys ──────────────────────────────────────────────────────────
const _kMode = 'theme_mode';
const _kAccent = 'accent_color';

// ── Shared prefs provider (overridden before ProviderScope in main.dart) ──────
final sharedPrefsProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('Override sharedPrefsProvider in main()'),
);

// ── State ─────────────────────────────────────────────────────────────────────
class ThemeState {
  const ThemeState({
    required this.mode,
    required this.accent,
  });

  final AppThemeMode mode;
  final AccentColor accent;

  ThemeMode get materialThemeMode {
    switch (mode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  ThemeData get lightTheme => AppTheme.light(accent);
  ThemeData get darkTheme => AppTheme.dark(accent);

  ThemeState copyWith({AppThemeMode? mode, AccentColor? accent}) => ThemeState(
        mode: mode ?? this.mode,
        accent: accent ?? this.accent,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────
class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier(this._prefs)
      : super(ThemeState(
          mode: _readMode(_prefs),
          accent: _readAccent(_prefs),
        ));

  final SharedPreferences _prefs;

  void setMode(AppThemeMode mode) {
    _prefs.setString(_kMode, mode.name);
    state = state.copyWith(mode: mode);
  }

  void setAccent(AccentColor accent) {
    _prefs.setString(_kAccent, accent.name);
    state = state.copyWith(accent: accent);
  }

  static AppThemeMode _readMode(SharedPreferences p) {
    final v = p.getString(_kMode);
    return AppThemeMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => AppThemeMode.dark,
    );
  }

  static AccentColor _readAccent(SharedPreferences p) {
    final v = p.getString(_kAccent);
    return AccentColor.values.firstWhere(
      (e) => e.name == v,
      orElse: () => AccentColor.cyan,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>(
  (ref) => ThemeNotifier(ref.read(sharedPrefsProvider)),
);
