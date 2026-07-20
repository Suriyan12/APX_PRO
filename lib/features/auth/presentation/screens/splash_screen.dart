import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
    _checkAuthAndRoute();
  }

  Future<void> _checkAuthAndRoute() async {
    // Wait for animation to finish before redirecting
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'jwt_access_token');

    if (!mounted) return;
    if (token != null) {
      context.go('/dashboard');
    } else {
      context.go('/onboarding');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Scaffold(
      backgroundColor: ext.background,
      body: GlassOrbBackground(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 24),
                Text(
                  'APX PRO',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: ext.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rehab, Posture & Fitness',
                  style: TextStyle(
                    fontSize: 14,
                    color: ext.textSecondary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
