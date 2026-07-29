import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthInterceptor extends Interceptor {
  final Dio _dio;
  final _storage = const FlutterSecureStorage();

  /// Set by AuthController so a failed token refresh (expired/rotated refresh
  /// token) can force the app back to a logged-out state. Without this the app
  /// keeps rendering protected screens after the session is unrecoverable.
  static void Function()? onSessionExpired;

  /// Guards against re-entrant refresh: while a refresh is in flight, any other
  /// 401s wait rather than each firing their own /auth/refresh.
  static Future<bool>? _refreshInFlight;

  // PRODUCTION: pass the full HTTPS base URL at build time — this is the only
  // thing a release build should use, and it must be https:
  //   flutter build apk --dart-define=API_BASE_URL=https://api.your-domain.com/api/v1
  //
  // DEVELOPMENT (when API_BASE_URL is not supplied): fall back to the local
  // dev backend over cleartext HTTP. Web → localhost; Android emulator →
  // 10.0.2.2; physical device → your PC's LAN IP. Override the host with:
  //   flutter run --dart-define=API_HOST=192.168.1.139
  // Dev cleartext is permitted only in debug builds (see the debug-only
  // network_security_config.xml); release builds forbid cleartext entirely.
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: '192.168.1.139', // ← dev PC Wi-Fi IP (ipconfig to confirm)
  );
  static final String baseUrl = _apiBaseUrl.isNotEmpty
      ? _apiBaseUrl
      : (kIsWeb
          ? 'http://localhost:8000/api/v1'
          : 'http://$_apiHost:8000/api/v1');
  AuthInterceptor(this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 1. Read access token from Secure Storage
    final token = await _storage.read(key: 'jwt_access_token');
    
    // 2. Append Bearer header if available
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Only a 401 on a *non-refresh* request is a candidate for token refresh.
    // Guarding the refresh path itself is critical: the refresh call must never
    // recurse back into this interceptor (that caused unbounded recursion).
    final isRefreshCall = err.requestOptions.path.contains('/auth/refresh');
    if (err.response?.statusCode != 401 || isRefreshCall) {
      return handler.next(err);
    }

    final refreshed = await _refreshTokens();
    if (!refreshed) {
      // Session is unrecoverable — clear it AND notify the app so the router
      // redirects to /login. Clearing storage alone left the UI stuck.
      await _storage.delete(key: 'jwt_access_token');
      await _storage.delete(key: 'jwt_refresh_token');
      onSessionExpired?.call();
      return handler.next(err);
    }

    // Replay the original request with the fresh access token.
    try {
      final newAccess = await _storage.read(key: 'jwt_access_token');
      final requestOptions = err.requestOptions;
      requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final cloneResponse = await _dio.fetch(requestOptions);
      return handler.resolve(cloneResponse);
    } catch (_) {
      return handler.next(err);
    }
  }

  /// Rotates tokens via a BARE Dio that has NO interceptor attached, so a 401
  /// from /auth/refresh can never re-enter onError. Concurrent 401s share a
  /// single in-flight refresh instead of stampeding the endpoint.
  Future<bool> _refreshTokens() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _storage.read(key: 'jwt_refresh_token');
    if (refreshToken == null) return false;
    try {
      final bareDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final response = await bareDio.post(
        '$baseUrl/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(contentType: Headers.jsonContentType),
      );
      if (response.statusCode == 200) {
        await _storage.write(
            key: 'jwt_access_token', value: response.data['access_token']);
        await _storage.write(
            key: 'jwt_refresh_token', value: response.data['refresh_token']);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
