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
    push.onTapPayload = _handleDeepLink;
    push.onForeground = _handleForeground;

    AuthController.onLogout = () async {
      await push.unregister();
      ref.read(notificationsProvider.notifier).reset();
    };

    await push.initialize();

    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.authenticated) {
      await push.syncToken();
      await ref.read(notificationsProvider.notifier).refreshUnread();
    }
  }

  /// Route a tapped notification to its destination.
  void _handleDeepLink(Map<String, dynamic> data) {
    final type = data['type'];
    final appointmentId = data['appointment_id'];
    if (type == 'appointment' &&
        appointmentId is String &&
        appointmentId.isNotEmpty) {
      ref.read(routerProvider).push('/appointments/$appointmentId');
    }
    // The badge is refreshed after any tap (the target screen marks it read).
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
            onPressed: () => _handleDeepLink(message.data),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeState = ref.watch(themeProvider);

    // Register the device token the moment the user becomes authenticated.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        final push = ref.read(pushServiceProvider);
        push.syncToken();
        ref.read(notificationsProvider.notifier).refreshUnread();
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
