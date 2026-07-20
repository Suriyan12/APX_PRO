import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:apx_pro/core/network/auth_interceptor.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AuthInterceptor.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Register our security interceptor
    _dio.interceptors.add(AuthInterceptor(_dio));

    // Debug-only logging. Bodies are never logged: multipart uploads and
    // ResponseType.bytes downloads would otherwise serialize megabytes of
    // binary to the console on every request (a major perf + memory cost).
    if (kDebugMode) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('→ ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('← ${response.statusCode} ${response.requestOptions.uri}');
          handler.next(response);
        },
        onError: (e, handler) {
          debugPrint('✗ ${e.type.name} ${e.requestOptions.uri}'
              '${e.response != null ? ' → HTTP ${e.response!.statusCode}' : ''}'
              ' | ${e.message ?? e.error ?? ''}');
          handler.next(e);
        },
      ));
    }
  }

  Dio get dio => _dio;

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Response> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.patch(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Exception _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Connection timed out. Please check your network.', 504);
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 500;
        return ApiException(_extractDetail(error.response?.data), statusCode);
      case DioExceptionType.connectionError:
        return ApiException('Could not connect to server. Please verify if backend is running.', 503);
      default:
        return ApiException('An unexpected network error occurred.', 500);
    }
  }

  /// Safely pull the `detail` message out of an error body. The body may be a
  /// JSON Map, a String, or — for requests made with ResponseType.bytes (file
  /// viewers/downloads) — a List<int>. Indexing a non-Map with 'detail' was
  /// throwing "type 'String' is not a subtype of type 'int' of 'index'".
  String _extractDetail(dynamic data) {
    const fallback = 'Something went wrong';
    if (data is Map) {
      final d = data['detail'];
      return d?.toString() ?? fallback;
    }
    if (data is List<int>) {
      // Error body returned as raw bytes — decode and parse JSON if possible.
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map && decoded['detail'] != null) {
          return decoded['detail'].toString();
        }
      } catch (_) {}
      return fallback;
    }
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map && decoded['detail'] != null) {
          return decoded['detail'].toString();
        }
      } catch (_) {}
      return fallback;
    }
    return fallback;
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: [$statusCode] $message';
}
