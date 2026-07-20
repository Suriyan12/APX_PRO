import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:apx_pro/core/firebase/firebase_phone_auth.dart';
import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';

/// Firebase phone-OTP screen.
///
/// The whole SMS flow (send, resend, auto-verification on Android, timeout)
/// runs on-device through Firebase Authentication. After Firebase confirms the
/// code, the resulting ID token is exchanged with the backend:
///   * mode == 'login'    → POST /auth/login/firebase   (existing accounts only)
///   * mode == 'register' → POST /auth/verify-phone     (activates the pending account)
class OtpScreen extends ConsumerStatefulWidget {
  final String phoneNumber;   // any format; normalized to E.164 internally
  final String mode;          // 'login' | 'register'
  final String? email;        // required for 'register'
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    this.mode = 'login',
    this.email,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  bool _sendingInitial = true;

  String? _verificationId;
  int? _resendToken;

  Timer? _resendTimer;
  int _resendCountdown = 60;

  String get _phoneE164 => FirebasePhoneAuth.normalizeE164(widget.phoneNumber);

  @override
  void initState() {
    super.initState();
    _sendCode(); // fire the first SMS as soon as the screen opens
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
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

  Future<void> _sendCode({bool isResend = false}) async {
    setState(() {
      if (isResend) {
        _isResending = true;
      } else {
        _sendingInitial = true;
      }
    });

    await FirebasePhoneAuth.sendOtp(
      phoneE164: _phoneE164,
      resendToken: isResend ? _resendToken : null,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _sendingInitial = false;
          _isResending = false;
        });
        _startResendTimer();
        if (isResend) {
          _showSnack('A new code has been sent.', context.ext.success);
        }
      },
      onAutoVerified: (idToken) async {
        // Android picked up the SMS automatically — no typing needed.
        if (!mounted) return;
        setState(() {
          _sendingInitial = false;
          _isResending = false;
        });
        await _completeWithToken(idToken);
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() {
          _sendingInitial = false;
          _isResending = false;
        });
        _showSnack(message, context.ext.error);
      },
    );
  }

  Future<void> _verify() async {
    if (_isLoading) return; // guard: auto-submit + button + auto-verify can race
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) {
      _showSnack('Please enter all 6 digits', context.ext.error);
      return;
    }
    if (_verificationId == null) {
      _showSnack('Please wait for the SMS to be sent, or tap Resend.',
          context.ext.error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final idToken = await FirebasePhoneAuth.confirmCode(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _completeWithToken(idToken);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      for (final c in _controllers) c.clear();
      _focusNodes.first.requestFocus();
      _showSnack(
          e.toString().replaceFirst('Exception: ', ''), context.ext.error);
    }
  }

  /// Firebase verified the phone — exchange the ID token with our backend.
  Future<void> _completeWithToken(String idToken) async {
    if (_isCompleting) return; // guard against double token exchange
    _isCompleting = true;
    setState(() => _isLoading = true);
    final auth = ref.read(authControllerProvider.notifier);

    final bool success;
    if (widget.mode == 'register' && widget.email != null) {
      success = await auth.verifyPhoneRegistration(widget.email!, idToken);
    } else {
      success = await auth.loginWithFirebase(idToken);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    _isCompleting = false;

    if (success) {
      context.go('/dashboard');
    } else {
      final msg = ref.read(authControllerProvider).errorMessage ??
          'Verification failed. Please try again.';
      _showSnack(msg, context.ext.error);
    }
  }

  bool _isCompleting = false;

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  widget.mode == 'register'
                      ? 'Verify Your Phone'
                      : 'Enter Verification Code',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: ext.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  _sendingInitial
                      ? 'Sending a 6-digit code to $_phoneE164…'
                      : 'We sent a 6-digit code to $_phoneE164.',
                  style: TextStyle(
                      fontSize: 15, color: ext.textSecondary),
                ),
                const SizedBox(height: 48),

                // OTP digit fields
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
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
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
                                  borderSide:
                                      BorderSide(color: ext.glassBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide:
                                      BorderSide(color: ext.glassBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                      color: ext.primary
                                          .withValues(alpha: 0.6),
                                      width: 1.5),
                                ),
                              ),
                              onChanged: (value) {
                                if (value.isNotEmpty && i < 5) {
                                  _focusNodes[i + 1].requestFocus();
                                }
                                if (value.isEmpty && i > 0) {
                                  _focusNodes[i - 1].requestFocus();
                                }
                                if (i == 5 && value.isNotEmpty) {
                                  _focusNodes[i].unfocus();
                                  _verify();
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

                // Resend row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Didn't receive the code? ",
                        style: TextStyle(color: ext.textSecondary)),
                    if (_isResending)
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ext.primary,
                        ),
                      )
                    else if (_resendCountdown > 0)
                      Text(
                        'Resend in ${_resendCountdown}s',
                        style: TextStyle(color: ext.textMuted),
                      )
                    else
                      GestureDetector(
                        onTap: () => _sendCode(isResend: true),
                        child: Text(
                          'Resend Code',
                          style: TextStyle(
                              color: ext.primary,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),

                // Verify button
                GlassButton(
                  label: 'Verify & Proceed',
                  onTap: _isLoading ? null : _verify,
                  style: GlassButtonStyle.primary,
                  loading: _isLoading,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
