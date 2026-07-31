import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:apx_pro/core/theme/colors.dart';
import 'package:apx_pro/core/theme/glass.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/notifications/data/notification_model.dart';
import 'package:apx_pro/features/notifications/presentation/controllers/notification_controller.dart';

/// The Notification Center: a paginated, pull-to-refresh list of the user's
/// notifications with unread highlighting, mark-as-read (tap) and mark-all-read.
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).loadInitial();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      ref.read(notificationsProvider.notifier).loadMore();
    }
  }

  Future<void> _onTapNotification(NotificationModel n) async {
    ref.read(notificationsProvider.notifier).markRead(n.id);
    // Deep-link: admins open Appointment Management; patients open details.
    final appointmentId = n.appointmentId;
    if (n.type == 'appointment' && appointmentId != null) {
      final isAdmin = ref.read(authControllerProvider).isAdmin;
      context.push(appointmentNotificationRoute(
        isAdmin: isAdmin,
        appointmentId: appointmentId,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Notifications',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (state.unread > 0)
            TextButton(
              onPressed: notifier.markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
        ],
      ),
      body: GlassOrbBackground(
        child: SafeArea(child: _buildBody(state, notifier)),
      ),
    );
  }

  Widget _buildBody(NotificationsState state, NotificationsNotifier notifier) {
    if (state.loading && state.items.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (state.error != null && state.items.isEmpty) {
      return _ErrorState(message: state.error!, onRetry: notifier.loadInitial);
    }
    if (state.items.isEmpty) {
      return const _EmptyState();
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: notifier.refresh,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        itemCount: state.items.length + 1,
        itemBuilder: (context, i) {
          if (i == state.items.length) return _footer(state);
          final n = state.items[i];
          return _NotificationCard(
            notification: n,
            onTap: () => _onTapNotification(n),
          );
        },
      ),
    );
  }

  Widget _footer(NotificationsState state) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      );
    }
    if (!state.hasMore && state.items.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('You’re all caught up',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final NotificationModel notification;
  final VoidCallback onTap;

  IconData get _icon {
    switch (notification.type) {
      case 'appointment':
        return Icons.event_available_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        tint: unread ? const Color(0x1400F2FE) : null,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight:
                                unread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6, top: 4),
                          decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Scrollable so pull-to-refresh works even when empty.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 140),
        Icon(Icons.notifications_none_rounded,
            color: AppColors.textMuted, size: 56),
        const SizedBox(height: 16),
        const Center(
          child: Text('No notifications yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text("You’ll see updates here as they arrive.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            GlassButton(
              label: 'Retry',
              style: GlassButtonStyle.primary,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
