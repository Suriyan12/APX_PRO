import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/notifications/data/notification_model.dart';
import 'package:apx_pro/features/notifications/data/notification_repository.dart';
import 'package:apx_pro/features/notifications/services/push_service.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider));
});

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(notificationRepositoryProvider));
});

// ── State ──────────────────────────────────────────────────────────────────

class NotificationsState {
  final bool loading; // first page
  final bool loadingMore; // subsequent pages
  final String? error;
  final List<NotificationModel> items;
  final int total;
  final int unread;

  const NotificationsState({
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.items = const [],
    this.total = 0,
    this.unread = 0,
  });

  bool get hasMore => items.length < total;

  NotificationsState copyWith({
    bool? loading,
    bool? loadingMore,
    String? error,
    List<NotificationModel>? items,
    int? total,
    int? unread,
    bool clearError = false,
  }) {
    return NotificationsState(
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      items: items ?? this.items,
      total: total ?? this.total,
      unread: unread ?? this.unread,
    );
  }
}

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  NotificationsNotifier(this._repo) : super(const NotificationsState());
  final NotificationRepository _repo;

  static const _pageSize = 20;

  /// Cheap badge refresh — used on login and on each foreground message.
  Future<void> refreshUnread() async {
    try {
      final count = await _repo.unreadCount();
      if (mounted) state = state.copyWith(unread: count);
    } catch (_) {
      // A badge refresh failure is non-critical; leave the previous value.
    }
  }

  Future<void> loadInitial() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _repo.list(limit: _pageSize, offset: 0);
      final unread = await _repo.unreadCount();
      state = state.copyWith(
        loading: false, items: page.items, total: page.total, unread: unread,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: _msg(e));
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await _repo.list(limit: _pageSize, offset: state.items.length);
      state = state.copyWith(
        loadingMore: false,
        items: [...state.items, ...page.items],
        total: page.total,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: _msg(e));
    }
  }

  Future<void> refresh() async {
    state = const NotificationsState();
    await loadInitial();
  }

  Future<void> markRead(String id) async {
    // Optimistic update.
    final idx = state.items.indexWhere((n) => n.id == id);
    if (idx == -1 || state.items[idx].isRead) return;
    final updated = [...state.items];
    updated[idx] = updated[idx].copyWith(isRead: true, readAt: DateTime.now());
    state = state.copyWith(
      items: updated,
      unread: (state.unread - 1).clamp(0, 1 << 31),
    );
    try {
      await _repo.markRead(id);
    } catch (_) {
      // Roll back on failure.
      final reverted = [...state.items];
      reverted[idx] = reverted[idx].copyWith(isRead: false);
      state = state.copyWith(items: reverted, unread: state.unread + 1);
    }
  }

  Future<void> markAllRead() async {
    final previous = state.items;
    final previousUnread = state.unread;
    state = state.copyWith(
      items: [for (final n in state.items) n.copyWith(isRead: true)],
      unread: 0,
    );
    try {
      await _repo.markAllRead();
    } catch (_) {
      state = state.copyWith(items: previous, unread: previousUnread);
    }
  }

  /// Called when the user logs out — clear any in-memory notifications.
  void reset() => state = const NotificationsState();

  String _msg(Object e) => e is ApiException ? e.message : 'Something went wrong.';
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>((ref) {
  return NotificationsNotifier(ref.watch(notificationRepositoryProvider));
});
