import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';

/// About Us — clinic story, services, and tappable contact actions
/// (dialer, email client, Instagram). Accessible to all roles from Settings.
class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  static const _phoneDisplay = '+91 91509 75521';
  static const _phoneE164 = '+919150975521';
  static const _email = 'aestheticperformx@gmail.com';
  static const _instagramHandle = '@aesthetic.performx';
  static const _instagramUser = 'aesthetic.performx';

  static const _services = [
    'Sports Physiotherapy and Injury Rehabilitation',
    'Assessment and Treatment of Musculoskeletal Injuries',
    'On-Field Sports Coverage and Training Support',
    'Strength and Conditioning Programs',
    'Injury Prevention Strategies',
    'Return-to-Play Testing and Performance Enhancement',
    'Athlete Screening and Movement Analysis',
    'Personalized Exercise and Rehabilitation Programs',
  ];

  // ── Contact actions ────────────────────────────────────────────────────────

  Future<void> _launch(BuildContext context, Uri uri,
      {LaunchMode mode = LaunchMode.platformDefault,
      String failMessage = 'Could not open the app for this action.'}) async {
    try {
      final ok = await launchUrl(uri, mode: mode);
      if (!ok && context.mounted) _showError(context, failMessage);
    } catch (_) {
      if (context.mounted) _showError(context, failMessage);
    }
  }

  void _openDialer(BuildContext context) => _launch(
        context,
        Uri(scheme: 'tel', path: _phoneE164),
        failMessage: 'No dialer app available on this device.',
      );

  void _openEmail(BuildContext context) => _launch(
        context,
        Uri(scheme: 'mailto', path: _email),
        failMessage: 'No email app available on this device.',
      );

  Future<void> _openInstagram(BuildContext context) async {
    // Prefer the Instagram app; fall back to the profile in the browser.
    final appUri = Uri.parse('instagram://user?username=$_instagramUser');
    final webUri = Uri.parse('https://www.instagram.com/$_instagramUser/');
    try {
      final openedApp =
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (openedApp) return;
    } catch (_) {
      // App not installed — fall through to the browser.
    }
    if (!context.mounted) return;
    await _launch(
      context,
      webUri,
      mode: LaunchMode.externalApplication,
      failMessage: 'Could not open Instagram.',
    );
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: context.ext.error),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Scaffold(
      backgroundColor: ext.background,
      appBar: GlassAppBar(
        title: 'About Us',
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
                // ── Brand header ──────────────────────────────────────────
                GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                            child: Icon(Icons.info_outline_rounded,
                                color: ext.primary, size: 26),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aesthetic PerformX',
                                  style: TextStyle(
                                    color: ext.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Led by Dr. Jeeva G, MPT (Sports)',
                                  style: TextStyle(
                                      color: ext.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Welcome to Aesthetic PerformX, where movement meets '
                        'performance and recovery meets excellence.\n\n'
                        'We specialize in helping athletes and active individuals '
                        'recover from injuries, improve performance, and return '
                        'to sport safely and confidently.',
                        style: TextStyle(
                          color: ext.textSecondary,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Services ──────────────────────────────────────────────
                _SectionLabel('Our Services', ext),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      for (var i = 0; i < _services.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle_rounded,
                                  color: ext.primary, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _services[i],
                                style: TextStyle(
                                  color: ext.textPrimary,
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Our goal is not only to treat pain and injuries but also to '
                    'optimize movement, enhance athletic performance, and help '
                    'every individual achieve their full potential.',
                    style: TextStyle(
                      color: ext.textSecondary,
                      fontSize: 13.5,
                      height: 1.55,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Contact ───────────────────────────────────────────────
                _SectionLabel('Get In Touch', ext),
                const SizedBox(height: 12),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ContactTile(
                        icon: Icons.phone_rounded,
                        label: 'Mobile',
                        value: _phoneDisplay,
                        ext: ext,
                        onTap: () => _openDialer(context),
                      ),
                      Divider(height: 1, color: ext.glassBorder),
                      _ContactTile(
                        icon: Icons.email_rounded,
                        label: 'Email',
                        value: _email,
                        ext: ext,
                        onTap: () => _openEmail(context),
                      ),
                      Divider(height: 1, color: ext.glassBorder),
                      _ContactTile(
                        icon: Icons.camera_alt_rounded,
                        label: 'Instagram',
                        value: _instagramHandle,
                        ext: ext,
                        onTap: () => _openInstagram(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Center(
                  child: Text(
                    'APX PRO  •  Aesthetic PerformX',
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

// ── Helper widgets ────────────────────────────────────────────────────────────

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

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AppThemeExtension ext;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.ext,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ext.primary.withValues(alpha: 0.12),
                border: Border.all(
                    color: ext.primary.withValues(alpha: 0.35), width: 1),
              ),
              child: Icon(icon, color: ext.primary, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                        color: ext.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                        color: ext.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500),
                  ),
                ],
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
