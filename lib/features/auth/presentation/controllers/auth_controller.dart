import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/core/network/auth_interceptor.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final String? userName;
  final String? userId;
  final String? userRole;
  final String? resetToken;

  AuthState({
    required this.status,
    this.errorMessage,
    this.userName,
    this.userId,
    this.userRole,
    this.resetToken,
  });

  bool get isAdmin => userRole?.toLowerCase() == 'admin';

  factory AuthState.initial() => AuthState(status: AuthStatus.initial);

  // Sentinel so copyWith can distinguish "leave unchanged" from "set to null".
  // Without it, passing null (e.g. to clear a stale error or a used reset token)
  // was a no-op — the old value lingered.
  static const Object _unset = Object();

  AuthState copyWith({
    AuthStatus? status,
    Object? errorMessage = _unset,
    String? userName,
    String? userId,
    String? userRole,
    Object? resetToken = _unset,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      userName: userName ?? this.userName,
      userId: userId ?? this.userId,
      userRole: userRole ?? this.userRole,
      resetToken: identical(resetToken, _unset)
          ? this.resetToken
          : resetToken as String?,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final ApiClient _apiClient;
  final _storage = const FlutterSecureStorage();

  AuthController(this._apiClient) : super(AuthState.initial()) {
    // When a token refresh fails irrecoverably, the interceptor clears storage
    // and calls this so the app leaves any protected screen for /login.
    AuthInterceptor.onSessionExpired = _forceLoggedOut;
    _checkAuthStatus();
  }

  void _forceLoggedOut() {
    if (!mounted) return;
    state = AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _checkAuthStatus() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    final token = await _storage.read(key: 'jwt_access_token');
    if (token != null) {
      final userName = await _storage.read(key: 'user_full_name');
      final userId = await _storage.read(key: 'user_id');
      final userRole = await _storage.read(key: 'user_role');
      state = AuthState(
        status: AuthStatus.authenticated,
        userName: userName ?? 'User',
        userId: userId,
        userRole: userRole,
      );
    } else {
      state = AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Password login. [identifier] may be an email address or a phone number —
  /// the backend resolves either.
  Future<bool> login(String identifier, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final response = await _apiClient.post(
        '/auth/login',
        data: {'username': identifier, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (response.statusCode == 200) {
        await _storeTokensAndState(response.data);
        return true;
      }
      state = AuthState(status: AuthStatus.error, errorMessage: 'Login failed.');
      return false;
    } catch (e) {
      state = AuthState(status: AuthStatus.error, errorMessage: _extractMessage(e));
      return false;
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    String verificationMethod = 'email',
  }) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final response = await _apiClient.post('/auth/register', data: {
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'password': password,
        'verification_method': verificationMethod,
      });
      if (response.statusCode == 201) {
        state = state.copyWith(status: AuthStatus.unauthenticated);
        return true;
      }
      state = AuthState(status: AuthStatus.error, errorMessage: 'Registration failed.');
      return false;
    } catch (e) {
      state = AuthState(status: AuthStatus.error, errorMessage: _extractMessage(e));
      return false;
    }
  }

  /// Verify a new account's email OTP. On success, tokens are stored (auto-login).
  Future<bool> verifyEmail(String email, String otp) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final response = await _apiClient.post('/auth/verify-email', data: {
        'email': email,
        'otp': otp,
      });
      if (response.statusCode == 200) {
        await _storeTokensAndState(response.data);
        return true;
      }
      state = AuthState(status: AuthStatus.error, errorMessage: 'Verification failed.');
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: _extractMessage(e),
      );
      return false;
    }
  }

  /// Resend the email-verification OTP for an unverified account.
  Future<bool> resendVerification(String email) async {
    try {
      await _apiClient.post('/auth/resend-verification', data: {'email': email});
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _extractMessage(e));
      return false;
    }
  }

  /// Phone-OTP login: Firebase has already verified the SMS code on-device;
  /// exchange its ID token for the app's JWT. Never creates an account.
  Future<bool> loginWithFirebase(String idToken) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final response = await _apiClient.post('/auth/login/firebase', data: {
        'id_token': idToken,
      });
      if (response.statusCode == 200) {
        await _storeTokensAndState(response.data);
        return true;
      }
      state = AuthState(status: AuthStatus.error, errorMessage: 'Login failed.');
      return false;
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: _extractMessage(e),
      );
      return false;
    }
  }

  /// Activate a pending phone-channel registration with a Firebase ID token.
  /// On success, tokens are stored (auto-login).
  Future<bool> verifyPhoneRegistration(String email, String idToken) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final response = await _apiClient.post('/auth/verify-phone', data: {
        'email': email,
        'id_token': idToken,
      });
      if (response.statusCode == 200) {
        await _storeTokensAndState(response.data);
        return true;
      }
      state = AuthState(status: AuthStatus.error, errorMessage: 'Verification failed.');
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: _extractMessage(e),
      );
      return false;
    }
  }

  // Step 1 — sends 6-digit OTP to user's email.
  // Returns false only on a network-level failure (server unreachable, no internet).
  // API-level errors (400/500) still return true: the backend always responds 200 to
  // prevent email enumeration, so any non-network error is indistinguishable from success.
  Future<bool> forgotPassword(String email) async {
    try {
      await _apiClient.post('/auth/forgot-password', data: {'email': email});
      return true;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        state = state.copyWith(
          errorMessage: 'Network error. Please check your connection and try again.',
        );
        return false;
      }
      // Non-network DioException (e.g. server returned 4xx/5xx): treat as success
      // to preserve anti-enumeration — the backend always returns 200 for registered emails too.
      return true;
    } catch (_) {
      return true;
    }
  }

  // Step 2 — verify email OTP, stores reset_token in state
  Future<bool> verifyForgotPasswordOtp(String email, String otp) async {
    try {
      final response = await _apiClient.post('/auth/forgot-password/verify', data: {
        'email': email,
        'otp': otp,
      });
      if (response.statusCode == 200) {
        final token = response.data['reset_token'] as String;
        state = state.copyWith(resetToken: token);
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: _extractMessage(e));
      return false;
    }
  }

  // Step 3 — set new password using reset_token
  Future<bool> resetPassword(String token, String newPassword) async {
    try {
      await _apiClient.post('/auth/reset-password', data: {
        'token': token,
        'new_password': newPassword,
      });
      state = state.copyWith(resetToken: null);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _extractMessage(e));
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    await _storage.deleteAll();
    state = AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _storeTokensAndState(Map<String, dynamic> data) async {
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;
    final user = data['user'] as Map<String, dynamic>;
    final fullName = user['full_name'] as String;
    final userId = user['id'] as String;
    final email = (user['email'] as String?) ?? '';
    final role = (user['role'] as String?) ?? 'PATIENT';

    await _storage.write(key: 'jwt_access_token', value: accessToken);
    await _storage.write(key: 'jwt_refresh_token', value: refreshToken);
    await _storage.write(key: 'user_full_name', value: fullName);
    await _storage.write(key: 'user_id', value: userId);
    await _storage.write(key: 'user_email', value: email);
    await _storage.write(key: 'user_role', value: role);

    state = AuthState(
      status: AuthStatus.authenticated,
      userName: fullName,
      userId: userId,
      userRole: role,
    );
  }

  String _extractMessage(Object e) {
    if (e is ApiException) return e.message;
    // Never surface raw exception/type-error text to users.
    return 'Something went wrong. Please try again.';
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(apiClientProvider));
});
