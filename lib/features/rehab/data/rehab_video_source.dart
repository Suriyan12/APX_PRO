import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:apx_pro/core/network/auth_interceptor.dart';

/// Where patient apps stream uploaded workout videos from.
///
/// Videos live in Google Drive; the backend proxies them through an
/// authenticated, Range-capable endpoint. The app never sees a Drive URL or a
/// server filesystem path — only this API route.
class RehabVideoSource {
  RehabVideoSource._();

  static Uri streamUri(String exerciseId) =>
      Uri.parse('${AuthInterceptor.baseUrl}/rehab/videos/$exerciseId');

  /// JWT header for the video player's HTTP requests (video_player performs
  /// its own requests, outside Dio's interceptors).
  static Future<Map<String, String>> authHeaders() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'jwt_access_token');
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }
}
