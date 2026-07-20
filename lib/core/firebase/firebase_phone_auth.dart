import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Thin wrapper around Firebase phone authentication.
///
/// The entire OTP lifecycle (send, resend, auto-verification on Android,
/// manual code entry, timeout) happens on the device through Firebase.
/// The backend never sees an SMS code — it only receives the Firebase
/// **ID token** produced after successful verification and validates it
/// server-side.
class FirebasePhoneAuth {
  FirebasePhoneAuth._();

  /// False until google-services.json + Firebase.initializeApp() are in place.
  static bool get isAvailable => Firebase.apps.isNotEmpty;

  static const notConfiguredMessage =
      'Phone verification is not set up yet. Please verify via email, '
      'or contact support.';

  /// 9876543210 → +919876543210 (Indian numbers; passes through E.164 input).
  static String normalizeE164(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (p.startsWith('+')) return p;
    if (p.startsWith('91') && p.length == 12) return '+$p';
    return '+91$p';
  }

  /// Starts phone-number verification (sends the SMS).
  ///
  /// [onCodeSent] receives the `verificationId` needed by [confirmCode] plus a
  /// resend token to pass back in for "Resend code".
  /// [onAutoVerified] fires on Android instant/auto verification with the
  /// final Firebase ID token — no manual code entry needed.
  /// [onFailed] receives a user-friendly error message.
  static Future<void> sendOtp({
    required String phoneE164,
    int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String idToken) onAutoVerified,
    required void Function(String message) onFailed,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!isAvailable) {
      onFailed(notConfiguredMessage);
      return;
    }
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneE164,
      timeout: timeout,
      forceResendingToken: resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final idToken = await _signIn(credential);
          onAutoVerified(idToken);
        } catch (e) {
          onFailed(_friendlyMessage(e));
        }
      },
      verificationFailed: (FirebaseAuthException e) =>
          onFailed(_friendlyMessage(e)),
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {
        // Auto-retrieval window closed — the user can still type the code.
      },
    );
  }

  /// Confirms a manually entered SMS code. Returns the Firebase ID token.
  /// Throws with a user-friendly message on invalid/expired codes.
  static Future<String> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _signIn(credential);
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendlyMessage(e));
    }
  }

  static Future<String> _signIn(PhoneAuthCredential credential) async {
    final result =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final idToken = await result.user?.getIdToken();
    if (idToken == null) {
      throw Exception('Verification failed. Please try again.');
    }
    // The Firebase session is only a vehicle for the ID token; the app's real
    // session is the backend JWT. Sign out so no Firebase state lingers.
    await FirebaseAuth.instance.signOut();
    return idToken;
  }

  static String _friendlyMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-verification-code':
          return 'Invalid code. Please check the SMS and try again.';
        case 'session-expired':
        case 'code-expired':
          return 'This code has expired. Please request a new one.';
        case 'invalid-phone-number':
          return 'That phone number is invalid.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a while and try again.';
        case 'network-request-failed':
          return 'Network error. Check your connection and try again.';
        default:
          return e.message ?? 'Phone verification failed. Please try again.';
      }
    }
    return e.toString().replaceFirst('Exception: ', '');
  }
}
