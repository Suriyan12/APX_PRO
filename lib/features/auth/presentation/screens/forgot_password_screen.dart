import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  int _step = 1; // 1=email  2=otp  3=new password
  bool _isLoading = false;
  bool _success = false;

  // Step 1
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  // Step 2
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(6, (_) => FocusNode());
  Timer? _resendTimer;
  int _resendCountdown = 0;

  // Step 3
  final _passwordFormKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (final c in _otpControllers) c.dispose();
    for (final f in _otpFocusNodes) f.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _submitEmail() async {
    if (_isLoading) return;
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final sent = await ref
        .read(authControllerProvider.notifier)
        .forgotPassword(_emailController.text.trim());

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!sent) {
      final msg = ref.read(authControllerProvider).errorMessage ??
          'Could not reach the server. Please check your connection.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: context.ext.error),
      );
      return;
    }

    _startResendTimer();
    setState(() => _step = 2);
  }

  Future<void> _verifyOtp() async {
    if (_isLoading) return; // guard: auto-submit + button can race
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all 6 digits')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await ref
        .read(authControllerProvider.notifier)
        .verifyForgotPasswordOtp(_emailController.text.trim(), code);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      setState(() => _step = 3);
    } else {
      for (final c in _otpControllers) c.clear();
      if (_otpFocusNodes.isNotEmpty) _otpFocusNodes.first.requestFocus();
      final msg =
          ref.read(authControllerProvider).errorMessage ?? 'Invalid OTP.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: context.ext.error),
      );
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCountdown > 0 || _isLoading) return;
    setState(() => _isLoading = true);

    await ref
        .read(authControllerProvider.notifier)
        .forgotPassword(_emailController.text.trim());

    if (!mounted) return;
    setState(() => _isLoading = false);
    _startResendTimer();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OTP resent — check your email.')),
    );
  }

  Future<void> _submitNewPassword() async {
    if (_isLoading) return;
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final resetToken = ref.read(authControllerProvider).resetToken ?? '';
    final success = await ref
        .read(authControllerProvider.notifier)
        .resetPassword(resetToken, _newPasswordController.text);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      setState(() => _success = true);
    } else {
      final msg = ref.read(authControllerProvider).errorMessage ??
          'Reset failed. Please start over.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: context.ext.error),
      );
    }
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
          onPressed: () {
            if (_success || _step == 1) {
              context.pop();
            } else {
              setState(() => _step--);
            }
          },
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: _success
                ? _buildSuccessView()
                : _step == 1
                    ? _buildEmailStep()
                    : _step == 2
                        ? _buildOtpStep()
                        : _buildNewPasswordStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    int? maxLength,
    String counterText = '',
    TextAlign textAlign = TextAlign.start,
    TextStyle? style,
    void Function(String)? onChanged,
    FocusNode? focusNode,
    List<TextInputFormatter>? inputFormatters,
    EdgeInsetsGeometry contentPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  }) {
    final ext = context.ext;
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
            focusNode: focusNode,
            keyboardType: keyboardType,
            obscureText: obscureText,
            maxLength: maxLength,
            textAlign: textAlign,
            inputFormatters: inputFormatters,
            style: style ?? TextStyle(color: ext.textPrimary),
            onChanged: onChanged,
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              counterText: counterText,
              contentPadding: contentPadding,
              hintStyle: TextStyle(color: ext.textMuted, fontSize: 13),
              prefixIcon: Icon(prefixIcon, color: ext.textMuted, size: 18),
              suffixIcon: suffixIcon,
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
                    width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailStep() {
    final ext = context.ext;
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepIndicator(1),
          const SizedBox(height: 28),
          Text(
            'Reset Password',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: ext.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            "Enter your registered email and we'll send a 6-digit OTP.",
            style: TextStyle(fontSize: 15, color: ext.textSecondary),
          ),
          const SizedBox(height: 48),
          _buildGlassTextField(
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
          const SizedBox(height: 32),
          GlassButton(
            label: 'Send OTP to Email',
            onTap: _isLoading ? null : _submitEmail,
            style: GlassButtonStyle.primary,
            loading: _isLoading,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    final ext = context.ext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(2),
        const SizedBox(height: 28),
        Text(
          'Check Your Email',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: ext.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit OTP sent to ${_emailController.text.trim()}',
          style: TextStyle(fontSize: 15, color: ext.textSecondary),
        ),
        const SizedBox(height: 48),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 48,
              height: 56,
              child: ClipRRect(
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
                      controller: _otpControllers[i],
                      focusNode: _otpFocusNodes[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: ext.textPrimary),
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
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
                              width: 1.5),
                        ),
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty && i < 5) {
                          _otpFocusNodes[i + 1].requestFocus();
                        }
                        if (val.isEmpty && i > 0) {
                          _otpFocusNodes[i - 1].requestFocus();
                        }
                        if (i == 5 && val.isNotEmpty) {
                          _otpFocusNodes[i].unfocus();
                          _verifyOtp();
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 36),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Didn't receive it? ",
                style: TextStyle(color: ext.textSecondary)),
            _resendCountdown > 0
                ? Text(
                    'Resend in ${_resendCountdown}s',
                    style: TextStyle(color: ext.textMuted),
                  )
                : GestureDetector(
                    onTap: _isLoading ? null : _resendOtp,
                    child: Text(
                      'Resend OTP',
                      style: TextStyle(
                          color: ext.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
          ],
        ),
        const SizedBox(height: 24),
        GlassButton(
          label: 'Verify OTP',
          onTap: _isLoading ? null : _verifyOtp,
          style: GlassButtonStyle.primary,
          loading: _isLoading,
          width: double.infinity,
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep() {
    final ext = context.ext;
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepIndicator(3),
          const SizedBox(height: 28),
          Text(
            'Set New Password',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: ext.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a strong password for your account.',
            style: TextStyle(fontSize: 15, color: ext.textSecondary),
          ),
          const SizedBox(height: 48),
          _buildGlassTextField(
            controller: _newPasswordController,
            hint: 'New Password',
            prefixIcon: Icons.lock_outlined,
            obscureText: _obscureNew,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNew
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: ext.textSecondary,
                size: 18,
              ),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 20),
          _buildGlassTextField(
            controller: _confirmPasswordController,
            hint: 'Confirm New Password',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscureConfirm,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: ext.textSecondary,
                size: 18,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) {
                return 'Please confirm your password';
              }
              if (v != _newPasswordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          Text(
            '8+ chars · uppercase · number · special character',
            style: TextStyle(color: ext.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 32),
          GlassButton(
            label: 'Reset Password',
            onTap: _isLoading ? null : _submitNewPassword,
            style: GlassButtonStyle.primary,
            loading: _isLoading,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    final ext = context.ext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 80, color: ext.success),
              const SizedBox(height: 24),
              Text(
                'Password Updated!',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: ext.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                'Your password has been reset successfully.\nLog in with your new password.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    color: ext.textSecondary,
                    height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        GlassButton(
          label: 'Go to Login',
          onTap: () => context.go('/login'),
          style: GlassButtonStyle.primary,
          width: double.infinity,
        ),
      ],
    );
  }

  Widget _buildStepIndicator(int current) {
    final ext = context.ext;
    return Row(
      children: List.generate(3, (i) {
        final step = i + 1;
        final isActive = step == current;
        final isDone = step < current;
        return Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isActive || isDone
                              ? ext.primary.withValues(alpha: 0.25)
                              : ext.glassTextFieldFill,
                          border: Border.all(
                            color: isActive || isDone
                                ? ext.primary.withValues(alpha: 0.7)
                                : ext.glassBorder,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: isDone
                          ? Icon(Icons.check,
                              size: 16, color: ext.primary)
                          : Text(
                              '$step',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isActive
                                    ? ext.primary
                                    : ext.textMuted,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (i < 2)
              Container(
                width: 44,
                height: 2,
                decoration: BoxDecoration(
                  gradient: isDone
                      ? LinearGradient(colors: [
                          ext.primary.withValues(alpha: 0.8),
                          ext.primary.withValues(alpha: 0.4),
                        ])
                      : null,
                  color: isDone ? null : ext.glassBorder,
                ),
              ),
          ],
        );
      }),
    );
  }
}
