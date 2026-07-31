import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apx_pro/core/router/app_router.dart';
import 'package:apx_pro/core/providers/theme_provider.dart';
import 'package:apx_pro/firebase_options.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:apx_pro/features/notifications/services/push_service.dart';

/// Root ScaffoldMessenger so foreground push messages can show an in-app banner
/// from anywhere, independent of the current screen.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Firebase powers phone-number sign-in and push notifications
  // (FlutterFire-generated config).
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // The background/terminated push handler must be registered before runApp.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  /// A deep-link captured before the user was authenticated (e.g. a terminated
  /// launch, where the FCM initial message arrives while the stored session is
  /// still loading). Processed once auth resolves. Always treated as a cold
  /// start, so the navigation stack is rebuilt beneath the detail.
  Map<String, dynamic>? _pendingDeepLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _bootstrapNotifications());
  }

  /// Wire push handlers once, register this device if already logged in, and
  /// hook logout so the token is deactivated. All best-effort — nothing here
  /// can break app startup.
  Future<void> _bootstrapNotifications() async {
    final push = ref.read(pushServiceProvider);
    push.onTapPayload = _onPushTap;
    push.onForeground = _handleForeground;

    AuthController.onLogout = () async {
      await push.unregister();
      ref.read(notificationsProvider.notifier).reset();
    };

    // initialize() may fire onTapPayload synchronously (getInitialMessage) —
    // if auth isn't ready yet, that tap is stored in _pendingDeepLink.
    await push.initialize();

    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.authenticated) {
      await push.syncToken();
      await ref.read(notificationsProvider.notifier).refreshUnread();
      _processPendingDeepLink();
    }
  }

  /// Entry point for every notification tap. Defers navigation until the user
  /// is authenticated (role must be known and the router must be past splash);
  /// otherwise routes immediately.
  void _onPushTap(Map<String, dynamic> data, {required bool fromColdStart}) {
    final auth = ref.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) {
      // Not ready (cold start still loading the session, or logged out) —
      // stash it and navigate once authenticated.
      _pendingDeepLink = data;
      return;
    }
    _navigateDeepLink(data, fromColdStart: fromColdStart);
  }

  /// Flush a deferred deep-link after auth resolves. It came from a cold start,
  /// so the stack is rebuilt beneath the detail.
  void _processPendingDeepLink() {
    final data = _pendingDeepLink;
    if (data == null) return;
    _pendingDeepLink = null;
    _navigateDeepLink(data, fromColdStart: true);
  }

  /// Route a tapped notification. Admins open Appointment Management
  /// (approve/reject); patients open Appointment Details. On a cold start the
  /// dashboard is placed beneath the detail so Back never lands on splash.
  void _navigateDeepLink(Map<String, dynamic> data,
      {required bool fromColdStart}) {
    final type = data['type'];
    final appointmentId = data['appointment_id'];
    if (type == 'appointment' &&
        appointmentId is String &&
        appointmentId.isNotEmpty) {
      final router = ref.read(routerProvider);
      final isAdmin = ref.read(authControllerProvider).isAdmin;
      final target = appointmentNotificationRoute(
        isAdmin: isAdmin,
        appointmentId: appointmentId,
      );

      if (fromColdStart) {
        // Rebuild the stack: Dashboard (base) → target. Push after the
        // dashboard frame settles so Back returns to it, not the splash route.
        router.go('/dashboard');
        WidgetsBinding.instance
            .addPostFrameCallback((_) => router.push(target));
      } else {
        // App already running — a normal push keeps the existing back stack.
        router.push(target);
      }

      // Mark the notification read after navigating (requirement 5). Works even
      // when the list isn't loaded (cold start) via a by-id API call.
      final notificationId = data['notification_id'];
      if (notificationId is String && notificationId.isNotEmpty) {
        ref.read(notificationsProvider.notifier).markReadById(notificationId);
        return;
      }
    }
    ref.read(notificationsProvider.notifier).refreshUnread();
  }

  /// Show an in-app banner for a foreground message and bump the badge.
  void _handleForeground(RemoteMessage message) {
    ref.read(notificationsProvider.notifier).refreshUnread();

    final n = message.notification;
    final title =
        n?.title ?? (message.data['title'] as String?) ?? 'New notification';
    final body = n?.body ?? (message.data['body'] as String?) ?? '';

    rootMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (body.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child:
                      Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => _onPushTap(message.data, fromColdStart: false),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeState = ref.watch(themeProvider);

    // Register the device token the moment the user becomes authenticated, and
    // flush any deep-link that arrived before login (e.g. a terminated launch).
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        final push = ref.read(pushServiceProvider);
        push.syncToken();
        ref.read(notificationsProvider.notifier).refreshUnread();
        _processPendingDeepLink();
      }
    });

    return MaterialApp.router(
      title: 'APX PRO',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: themeState.lightTheme,
      darkTheme: themeState.darkTheme,
      themeMode: themeState.materialThemeMode,
      themeAnimationDuration: const Duration(milliseconds: 260),
      themeAnimationCurve: Curves.easeOutCubic,
      routerConfig: router,
    );
  }
}
