import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _acceptTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String _verifyMethod = 'email'; // 'email' | 'phone'

  Widget _methodChip(String value, String label, IconData icon, ext) {
    final selected = _verifyMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _verifyMethod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? ext.primary.withValues(alpha: 0.13)
              : ext.glassTextFieldFill,
          border: Border.all(
            color: selected ? ext.primary.withValues(alpha: 0.6) : ext.glassBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? ext.primary : ext.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected ? ext.primary : ext.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Please enter a password';
    if (v.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) {
      return 'Must include at least one uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(v)) {
      return 'Must include at least one number';
    }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(v)) {
      return 'Must include at least one special character (!@#\$%...)';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Terms & Conditions to continue.'),
        ),
      );
      return;
    }

    if (_verifyMethod == 'phone' && _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a phone number to verify via SMS.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final registered =
        await ref.read(authControllerProvider.notifier).register(
              fullName: _nameController.text.trim(),
              email: _emailController.text.trim(),
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
              verificationMethod: _verifyMethod,
            );

    if (!mounted) return;

    if (!registered) {
      setState(() => _isLoading = false);
      final msg =
          ref.read(authControllerProvider).errorMessage ?? 'Registration failed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    // Account is PENDING — verify via the chosen channel before it can be used.
    setState(() => _isLoading = false);
    if (_verifyMethod == 'phone') {
      // Firebase sends + verifies the SMS code; the backend then activates the
      // account from the resulting ID token.
      context.push('/otp', extra: {
        'phone': _phoneController.text.trim(),
        'mode': 'register',
        'email': _emailController.text.trim(),
      });
    } else {
      context.push('/verify-email', extra: {
        'email': _emailController.text.trim(),
        'channel': 'email',
      });
    }
  }

  Widget _glassField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return ClipRRect(
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
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            obscureText: obscureText,
            style: TextStyle(color: context.ext.textPrimary),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: context.ext.textMuted, fontSize: 13),
              prefixIcon: Icon(prefixIcon, color: context.ext.textMuted, size: 18),
              suffixIcon: suffixIcon,
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
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: context.ext.error.withValues(alpha: 0.6),
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: context.ext.error.withValues(alpha: 0.8),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return Scaffold(
      backgroundColor: ext.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: '',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: ext.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 72,
                      height: 72,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create Account',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: ext.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Begin your rehabilitation and posture improvement program today.',
                    style: TextStyle(fontSize: 15, color: ext.textSecondary),
                  ),
                  const SizedBox(height: 36),

                  _glassField(
                    controller: _nameController,
                    hint: 'Full Name',
                    prefixIcon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your full name';
                      }
                      if (v.trim().length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  _glassField(
                    controller: _emailController,
                    hint: 'Email Address',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$')
                          .hasMatch(v.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  _glassField(
                    controller: _phoneController,
                    hint: '9876543210',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your mobile number';
                      }
                      final digits =
                          v.trim().replaceAll(RegExp(r'[\s\-\+]'), '');
                      if (!RegExp(r'^(91)?[6-9][0-9]{9}$').hasMatch(digits)) {
                        return 'Please enter a valid 10-digit Indian mobile number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  _glassField(
                    controller: _passwordController,
                    hint: 'Password',
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: ext.textMuted,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 20),

                  _glassField(
                    controller: _confirmPasswordController,
                    hint: 'Confirm Password',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscureConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: ext.textMuted,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (v != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Minimum 8 characters • 1 uppercase letter • 1 number • 1 special ',
                    style: TextStyle(color: ext.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),

                  // Verification channel choice (verify one, not both).
                  Text(
                    'Verify my account via',
                    style: TextStyle(
                        color: ext.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _methodChip('email', 'Email',
                              Icons.email_outlined, ext)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _methodChip('phone', 'Phone (SMS)',
                              Icons.sms_outlined, ext)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _acceptTerms,
                          onChanged: (v) =>
                              setState(() => _acceptTerms = v ?? false),
                          activeColor: ext.primary,
                          checkColor: ext.background,
                          side: const BorderSide(color: Color(0x40FFFFFF), width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'I accept the Terms of Service & Privacy Policy',
                          style: TextStyle(
                              color: ext.textPrimary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  GlassButton(
                    label: 'Create Account',
                    onTap: _isLoading ? null : _submit,
                    style: GlassButtonStyle.primary,
                    loading: _isLoading,
                    width: double.infinity,
                  ),
                  const SizedBox(height: 32),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account? ',
                          style: TextStyle(color: ext.textSecondary)),
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Text(
                          'Log In',
                          style: TextStyle(
                              color: ext.primary,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
