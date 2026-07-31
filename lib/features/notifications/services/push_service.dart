import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:apx_pro/features/notifications/data/notification_repository.dart';

/// Top-level background handler. Must be a top-level (or static) function and
/// annotated so it survives tree-shaking / runs in a background isolate. The OS
/// renders the tray notification from the message's `notification` block; we do
/// no heavy work here (no app state is available in this isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal — kept for completeness and future background work.
  debugPrint('[push] background message: ${message.messageId}');
}

/// Wraps FirebaseMessaging so the rest of the app never imports it directly.
/// Every Firebase call is guarded: if messaging is unavailable (no permission,
/// web without a VAPID key, or any platform error) push is silently disabled
/// and the REST-backed Notification Center keeps working.
class PushService {
  PushService(this._repo);

  final NotificationRepository _repo;
  final FirebaseMessaging _fm = FirebaseMessaging.instance;

  bool _initialized = false;

  /// Invoked when a message is tapped (from background or terminated) or is
  /// received in the foreground and the user chooses to view it. Receives the
  /// message's `data` payload for deep-link routing. `fromColdStart` is true
  /// only for the message that launched a terminated app (getInitialMessage),
  /// so the handler can build a full navigation stack instead of pushing onto
  /// the transient splash route.
  void Function(Map<String, dynamic> data, {required bool fromColdStart})?
      onTapPayload;

  /// Invoked for every foreground message so the UI can refresh the badge and
  /// surface an in-app banner.
  void Function(RemoteMessage message)? onForeground;

  /// Wire up permissions and message handlers. Safe to call once at startup;
  /// never throws.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      // iOS: present alerts while the app is foregrounded.
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      // Terminated-state tap: the message that launched the app. Marked as a
      // cold start so the handler can defer until auth resolves and rebuild the
      // navigation stack (Dashboard → detail).
      final initial = await _fm.getInitialMessage();
      if (initial != null) {
        onTapPayload?.call(initial.data, fromColdStart: true);
      }

      // Background → foreground tap (app already running).
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        onTapPayload?.call(m.data, fromColdStart: false);
      });

      // Foreground message.
      FirebaseMessaging.onMessage.listen((m) {
        onForeground?.call(m);
      });

      // Token rotation → re-register with the backend.
      _fm.onTokenRefresh.listen((token) {
        _safeRegister(token);
      });

      _initialized = true;
      debugPrint('[push] initialized');
    } catch (e) {
      debugPrint('[push] initialize failed (push disabled): $e');
    }
  }

  /// Register the current device's token for the logged-in user. Best-effort.
  Future<void> syncToken() async {
    try {
      final token = await _currentToken();
      if (token == null || token.isEmpty) {
        debugPrint('[push] no FCM token available; skipping registration');
        return;
      }
      await _safeRegister(token);
    } catch (e) {
      debugPrint('[push] syncToken failed: $e');
    }
  }

  /// Deactivate this device's token (call on logout). Best-effort; never throws.
  Future<void> unregister() async {
    try {
      final token = await _currentToken();
      if (token != null && token.isNotEmpty) {
        await _repo.unregisterDevice(token);
      }
    } catch (e) {
      debugPrint('[push] unregister failed: $e');
    }
  }

  Future<void> _safeRegister(String token) async {
    try {
      await _repo.registerDevice(token: token, platform: _platform());
      debugPrint('[push] device token registered');
    } catch (e) {
      debugPrint('[push] registerDevice failed: $e');
    }
  }

  Future<String?> _currentToken() async {
    // On web, getToken needs the project's Web Push (VAPID) key. Supply it at
    // build time with --dart-define=FCM_VAPID_KEY=...; without it, web push is
    // disabled but everything else keeps working.
    if (kIsWeb) {
      const vapid = String.fromEnvironment('FCM_VAPID_KEY');
      return _fm.getToken(vapidKey: vapid.isEmpty ? null : vapid);
    }
    return _fm.getToken();
  }

  String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'other';
    }
  }
}
