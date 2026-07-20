import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final success = await ref.read(authControllerProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.go('/dashboard');
    } else {
      final msg = ref.read(authControllerProvider).errorMessage ?? 'Login failed';
      // Pending (unverified) account → route to the right verification screen.
      if (msg.contains('ACCOUNT_NOT_VERIFIED')) {
        final identifier = _emailController.text.trim();
        if (identifier.contains('@')) {
          context.push('/verify-email', extra: {'email': identifier});
        } else {
          // Phone-channel pending account: Firebase OTP both verifies and logs in.
          context.push('/otp', extra: {'phone': identifier, 'mode': 'login'});
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
      );
    }
  }

  void _showOtpPhoneDialog() {
    _phoneController.clear();
    showGlassDialog<void>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter Mobile Number',
              style: TextStyle(
                color: context.ext.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    style: TextStyle(color: context.ext.textPrimary),
                    decoration: InputDecoration(
                      hintText: '+91 98765 43210',
                      hintStyle: TextStyle(color: context.ext.textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.phone_outlined, color: context.ext.textMuted, size: 18),
                      filled: true,
                      fillColor: context.ext.glassTextFieldFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: context.ext.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: context.ext.glassBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: context.ext.primary.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                    style: GlassButtonStyle.ghost,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Send OTP',
                    onTap: () {
                      final phone = _phoneController.text.trim();
                      final digits =
                          phone.replaceAll(RegExp(r'[\s\-\+]'), '');
                      if (!RegExp(r'^(91)?[6-9][0-9]{9}$').hasMatch(digits)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid 10-digit mobile number.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).pop();
                      // The OTP screen sends the SMS via Firebase on open.
                      context.push('/otp',
                          extra: {'phone': phone, 'mode': 'login'});
                    },
                    style: GlassButtonStyle.primary,
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Scaffold(
      backgroundColor: ext.background,
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 80,
                      height: 80,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: ext.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Log in to continue your recovery journey.',
                    style: TextStyle(fontSize: 15, color: ext.textSecondary),
                  ),
                  const SizedBox(height: 48),

                  // Email field
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(color: Colors.transparent),
                          ),
                        ),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: ext.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Email or Phone Number',
                            hintStyle: TextStyle(color: ext.textMuted, fontSize: 13),
                            prefixIcon: Icon(Icons.person_outline_rounded, color: ext.textMuted, size: 18),
                            filled: true,
                            fillColor: ext.glassTextFieldFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: ext.glassBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: ext.glassBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: ext.primary.withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter your email or phone number';
                            }
                            final value = v.trim();
                            final isEmail = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$')
                                .hasMatch(value);
                            final digits =
                                value.replaceAll(RegExp(r'[\s\-\+]'), '');
                            final isPhone =
                                RegExp(r'^(91)?[6-9][0-9]{9}$').hasMatch(digits);
                            if (!isEmail && !isPhone) {
                              return 'Enter a valid email or 10-digit phone number';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Password field
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(color: Colors.transparent),
                          ),
                        ),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: ext.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            hintStyle: TextStyle(color: ext.textMuted, fontSize: 13),
                            prefixIcon: Icon(Icons.lock_outlined, color: ext.textMuted, size: 18),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: ext.textSecondary,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            filled: true,
                            fillColor: ext.glassTextFieldFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: ext.glassBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: ext.glassBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: ext.primary.withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Please enter your password';
                            if (v.length < 6) return 'Password must be at least 6 characters';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => context.push('/forgot-password'),
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: ext.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Primary login button
                  GlassButton(
                    label: 'Log In',
                    onTap: _isLoading ? null : _submit,
                    style: GlassButtonStyle.primary,
                    loading: _isLoading,
                    width: double.infinity,
                  ),
                  const SizedBox(height: 16),

                  // OTP login button (secondary)
                  GlassButton(
                    label: 'Log In via Mobile OTP',
                    icon: Icons.phone_iphone_rounded,
                    onTap: _isLoading ? null : _showOtpPhoneDialog,
                    style: GlassButtonStyle.ghost,
                    width: double.infinity,
                  ),
                  const SizedBox(height: 40),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(color: ext.textSecondary),
                      ),
                      GestureDetector(
                        onTap: () => context.push('/register'),
                        child: Text(
                          'Register',
                          style: TextStyle(
                            color: ext.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
