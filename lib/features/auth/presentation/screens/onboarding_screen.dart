import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingItem> _slides = [
    OnboardingItem(
      title: 'APX Scan Posture Check',
      description: 'Upload video scans of your posture. Our senior mobile team and physiotherapists evaluate alignment to prevent injuries.',
      icon: Icons.camera_alt_rounded,
    ),
    OnboardingItem(
      title: 'Personalized Rehab programs',
      description: 'Gain access to premium, daily exercise modules crafted specifically for rehabilitation and muscle recovery.',
      icon: Icons.fitness_center_rounded,
    ),
    OnboardingItem(
      title: 'Physiotherapist Bookings',
      description: 'Consult directly with professional physiotherapists. Secure appointment slots, review schedules, and track outcomes.',
      icon: Icons.calendar_month_rounded,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Scaffold(
      backgroundColor: ext.background,
      body: GlassOrbBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Logo + skip row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset('assets/images/logo.png', width: 40, height: 40),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        borderRadius: BorderRadius.circular(20),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: ext.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: _slides.length,
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GlassCard(
                            padding: const EdgeInsets.all(32),
                            borderRadius: BorderRadius.circular(32),
                            tint: const Color(0x1400F2FE),
                            child: Icon(
                              slide.icon,
                              size: 72,
                              color: ext.primary,
                            ),
                          ),
                          const SizedBox(height: 48),
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: ext.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            slide.description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: ext.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // Dots & Next button row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Indicators
                    Row(
                      children: List.generate(
                        _slides.length,
                        (index) => Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? ext.primary
                                : ext.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    // Button
                    GlassButton(
                      label: _currentPage == _slides.length - 1
                          ? 'Get Started'
                          : 'Next',
                      onTap: () {
                        if (_currentPage < _slides.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeIn,
                          );
                        } else {
                          context.go('/login');
                        }
                      },
                      style: GlassButtonStyle.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingItem {
  final String title;
  final String description;
  final IconData icon;

  OnboardingItem({
    required this.title,
    required this.description,
    required this.icon,
  });
}
