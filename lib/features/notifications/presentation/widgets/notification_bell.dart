import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:apx_pro/core/theme/app_theme_extension.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/notifications/presentation/controllers/notification_controller.dart';

/// A glass bell button with an unread badge. Opens the Notification Center.
/// Watches [notificationsProvider] so the badge stays live as notifications
/// are read or arrive in the foreground.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = context.ext;
    final unread = ref.watch(notificationsProvider.select((s) => s.unread));

    return GestureDetector(
      onTap: () => context.push('/notifications'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GlassCard(
            padding: const EdgeInsets.all(10),
            borderRadius: BorderRadius.circular(50),
            child: Icon(Icons.notifications_rounded,
                color: ext.primary, size: 22),
          ),
          if (unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: ext.accentPink,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: ext.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
