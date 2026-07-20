import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/core/theme/theme.dart';
import 'package:apx_pro/core/providers/theme_provider.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = context.ext;
    final themeState = ref.watch(themeProvider);
    final authState = ref.watch(authControllerProvider);
    final userName = authState.userName ?? '';

    return Scaffold(
      backgroundColor: ext.background,
      appBar: GlassAppBar(
        title: 'Settings',
        leading: GestureDetector(
          onTap: context.pop,
          child: Icon(Icons.arrow_back_ios_new_rounded,
              color: ext.textSecondary, size: 20),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Profile summary ────────────────────────────────────────
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ext.primary.withValues(alpha: 0.15),
                          border: Border.all(
                              color: ext.primary.withValues(alpha: 0.40),
                              width: 1.5),
                        ),
                        child: Icon(Icons.person_rounded,
                            color: ext.primary, size: 26),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName.isNotEmpty ? userName : 'Account',
                              style: TextStyle(
                                color: ext.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              authState.isAdmin ? 'Administrator' : 'Patient',
                              style: TextStyle(
                                  color: ext.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Appearance ────────────────────────────────────────────
                _SectionLabel('Appearance', ext),
                const SizedBox(height: 12),

                // Theme mode
                GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme',
                        style: TextStyle(
                          color: ext.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _ThemeModeChip(
                            label: 'Dark',
                            icon: Icons.dark_mode_rounded,
                            selected: themeState.mode == AppThemeMode.dark,
                            onTap: () => ref
                                .read(themeProvider.notifier)
                                .setMode(AppThemeMode.dark),
                            ext: ext,
                          ),
                          const SizedBox(width: 8),
                          _ThemeModeChip(
                            label: 'Light',
                            icon: Icons.light_mode_rounded,
                            selected: themeState.mode == AppThemeMode.light,
                            onTap: () => ref
                                .read(themeProvider.notifier)
                                .setMode(AppThemeMode.light),
                            ext: ext,
                          ),
                          const SizedBox(width: 8),
                          _ThemeModeChip(
                            label: 'System',
                            icon: Icons.brightness_auto_rounded,
                            selected: themeState.mode == AppThemeMode.system,
                            onTap: () => ref
                                .read(themeProvider.notifier)
                                .setMode(AppThemeMode.system),
                            ext: ext,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Accent color
                GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accent Colour',
                        style: TextStyle(
                          color: ext.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _AccentChip(
                            label: 'Cyan',
                            darkColor: const Color(0xFF00F2FE),
                            lightColor: const Color(0xFF00B4D8),
                            selected: themeState.accent == AccentColor.cyan,
                            onTap: () => ref
                                .read(themeProvider.notifier)
                                .setAccent(AccentColor.cyan),
                            ext: ext,
                          ),
                          const SizedBox(width: 8),
                          _AccentChip(
                            label: 'Blue',
                            darkColor: const Color(0xFF4FC3F7),
                            lightColor: const Color(0xFF0288D1),
                            selected: themeState.accent == AccentColor.blue,
                            onTap: () => ref
                                .read(themeProvider.notifier)
                                .setAccent(AccentColor.blue),
                            ext: ext,
                          ),
                          const SizedBox(width: 8),
                          _AccentChip(
                            label: 'Purple',
                            darkColor: const Color(0xFFCE93D8),
                            lightColor: const Color(0xFF7B1FA2),
                            selected: themeState.accent == AccentColor.purple,
                            onTap: () => ref
                                .read(themeProvider.notifier)
                                .setAccent(AccentColor.purple),
                            ext: ext,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── About ─────────────────────────────────────────────────
                _SectionLabel('About', ext),
                const SizedBox(height: 12),

                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        label: 'About Us',
                        ext: ext,
                        onTap: () => context.push('/settings/about'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Account ───────────────────────────────────────────────
                _SectionLabel('Account', ext),
                const SizedBox(height: 12),

                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.logout_rounded,
                        label: 'Log Out',
                        color: ext.accentPink,
                        ext: ext,
                        onTap: () async {
                          await ref
                              .read(authControllerProvider.notifier)
                              .logout();
                          if (context.mounted) context.go('/login');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // App version
                Center(
                  child: Text(
                    'APX PRO  v1.0.0',
                    style: TextStyle(
                        color: ext.textMuted, fontSize: 12, letterSpacing: 0.3),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppThemeExtension ext;
  const _SectionLabel(this.text, this.ext);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: ext.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ThemeModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final AppThemeExtension ext;

  const _ThemeModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.ext,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? ext.primary.withValues(alpha: 0.15)
                : ext.glassTextFieldFill,
            border: Border.all(
              color: selected
                  ? ext.primary.withValues(alpha: 0.50)
                  : ext.glassBorder,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20, color: selected ? ext.primary : ext.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? ext.primary : ext.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentChip extends StatelessWidget {
  final String label;
  final Color darkColor;
  final Color lightColor;
  final bool selected;
  final VoidCallback onTap;
  final AppThemeExtension ext;

  const _AccentChip({
    required this.label,
    required this.darkColor,
    required this.lightColor,
    required this.selected,
    required this.onTap,
    required this.ext,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = ext.isDark ? darkColor : lightColor;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? swatch.withValues(alpha: 0.15)
                : ext.glassTextFieldFill,
            border: Border.all(
              color:
                  selected ? swatch.withValues(alpha: 0.60) : ext.glassBorder,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: swatch,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: swatch.withValues(alpha: 0.40),
                            blurRadius: 8,
                            spreadRadius: -1,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? swatch : ext.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final AppThemeExtension ext;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.ext,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ext.textPrimary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: c, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: ext.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}
