import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';

/// Email-OTP verification for a newly registered account. On success the
/// backend auto-logs the user in (tokens stored) and we go to the dashboard.
/// (Phone-channel registrations verify via Firebase on the /otp screen.)
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String email;
  final String? channel; // kept for route compatibility; always 'email' now
  const VerifyEmailScreen({super.key, required this.email, this.channel});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _otpController = TextEditingController();
  bool _verifying = false;
  bool _resending = false;

  // Resend cooldown — mirrors the backend's 60s throttle so the button is
  // disabled with a live countdown instead of letting users spam it.
  Timer? _resendTimer;
  int _resendCountdown = 60;

  @override
  void initState() {
    super.initState();
    // A code was just sent on registration; start the cooldown immediately.
    _startResendTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
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

  Future<void> _verify() async {
    if (_verifying) return; // guard against double-submit
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code from your email.')),
      );
      return;
    }
    setState(() => _verifying = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .verifyEmail(widget.email, otp);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      context.go('/dashboard');
    } else {
      final msg =
          ref.read(authControllerProvider).errorMessage ?? 'Verification failed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: context.ext.error),
      );
    }
  }

  Future<void> _resend() async {
    if (_resending || _resendCountdown > 0) return;
    setState(() => _resending = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .resendVerification(widget.email);
    if (!mounted) return;
    setState(() => _resending = false);
    if (ok) _startResendTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'A new code has been sent to ${widget.email}.'
            : 'Could not resend the code. Please try again.'),
        backgroundColor: ok ? context.ext.success : context.ext.error,
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
        title: 'Verify Email',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: ext.textPrimary, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: GlassOrbBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.mark_email_read_rounded,
                    color: ext.primary, size: 56),
                const SizedBox(height: 20),
                Text(
                  'Verify your email',
                  style: TextStyle(
                    color: ext.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a 6-digit code to\n${widget.email}',
                  style: TextStyle(
                      color: ext.textSecondary, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                GlassTextField(
                  controller: _otpController,
                  hintText: 'Enter 6-digit code',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: ext.textMuted, size: 18),
                ),
                const SizedBox(height: 12),
                GlassButton(
                  label: 'Verify & Continue',
                  loading: _verifying,
                  onTap: _verify,
                  width: double.infinity,
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: (_resending || _resendCountdown > 0) ? null : _resend,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _resending
                            ? 'Sending…'
                            : _resendCountdown > 0
                                ? 'Resend code in ${_resendCountdown}s'
                                : "Didn't get it? Resend code",
                        style: TextStyle(
                            color: _resendCountdown > 0
                                ? ext.textMuted
                                : ext.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
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
