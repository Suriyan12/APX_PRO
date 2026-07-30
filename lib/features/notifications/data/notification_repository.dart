import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/notifications/data/notification_model.dart';

/// REST client for the Notification Center. Wraps the Phase-1 backend endpoints
/// under /notifications. Uses the shared authenticated ApiClient (Bearer token
/// attached by AuthInterceptor).
class NotificationRepository {
  final ApiClient _api;
  NotificationRepository(this._api);

  // ── Device registration ────────────────────────────────────────────────────

  Future<void> registerDevice({required String token, String? platform}) async {
    await _api.post('/notifications/devices', data: {
      'token': token,
      if (platform != null) 'platform': platform,
    });
  }

  Future<void> unregisterDevice(String token) async {
    await _api.post('/notifications/devices/unregister', data: {'token': token});
  }

  // ── Notifications ───────────────────────────────────────────────────────────

  Future<NotificationPage> list({
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final r = await _api.get('/notifications', queryParameters: {
      'limit': limit,
      'offset': offset,
      if (unreadOnly) 'unread_only': true,
    });
    return NotificationPage.fromJson(r.data as Map<String, dynamic>);
  }

  Future<int> unreadCount() async {
    final r = await _api.get('/notifications/unread-count');
    return (r.data['count'] as num?)?.toInt() ?? 0;
  }

  Future<NotificationModel> markRead(String id) async {
    final r = await _api.put('/notifications/$id/read');
    return NotificationModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<int> markAllRead() async {
    final r = await _api.put('/notifications/read-all');
    return (r.data['updated'] as num?)?.toInt() ?? 0;
  }
}
