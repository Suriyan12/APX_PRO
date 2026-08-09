import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/auth/presentation/controllers/auth_controller.dart';
import 'package:apx_pro/features/help_center/data/help_models.dart';
import 'package:apx_pro/features/help_center/data/help_repository.dart';

// ── Core provider ─────────────────────────────────────────────────────────────

final helpRepositoryProvider = Provider<HelpRepository>((ref) {
  return HelpRepository(ref.watch(apiClientProvider));
});

// ── User: Help Center (active videos, grouped by category) ────────────────────

@immutable
class HelpCenterState {
  final bool loading;
  final String? error;
  final List<HelpVideoModel> all; // active videos, ordered by (category, order)
  final List<String> categories; // supported categories (for filter chips)
  final String searchQuery;
  final String? categoryFilter;

  const HelpCenterState({
    this.loading = false,
    this.error,
    this.all = const [],
    this.categories = const [],
    this.searchQuery = '',
    this.categoryFilter,
  });

  HelpCenterState copyWith({
    bool? loading,
    String? error,
    List<HelpVideoModel>? all,
    List<String>? categories,
    String? searchQuery,
    String? categoryFilter,
    bool clearError = false,
    bool clearCategory = false,
  }) {
    return HelpCenterState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      all: all ?? this.all,
      categories: categories ?? this.categories,
      searchQuery: searchQuery ?? this.searchQuery,
      categoryFilter:
          clearCategory ? null : (categoryFilter ?? this.categoryFilter),
    );
  }

  bool get isSearching => searchQuery.trim().isNotEmpty;

  /// The featured tutorial, if one is active. Hidden while searching/filtering
  /// so results are unambiguous.
  HelpVideoModel? get featured {
    if (isSearching || categoryFilter != null) return null;
    for (final v in all) {
      if (v.isFeatured) return v;
    }
    return null;
  }

  /// Videos after applying search + category filter. Excludes the featured
  /// video when it is being shown separately at the top.
  List<HelpVideoModel> get _visible {
    final q = searchQuery.trim().toLowerCase();
    final featuredId = featured?.id;
    return all.where((v) {
      if (v.id == featuredId) return false;
      if (categoryFilter != null && v.category != categoryFilter) return false;
      if (q.isEmpty) return true;
      return v.title.toLowerCase().contains(q) ||
          (v.description ?? '').toLowerCase().contains(q) ||
          v.category.toLowerCase().contains(q);
    }).toList();
  }

  /// Visible videos grouped by category, preserving category order as it first
  /// appears in the (already category-ordered) list.
  Map<String, List<HelpVideoModel>> get grouped {
    final map = <String, List<HelpVideoModel>>{};
    for (final v in _visible) {
      map.putIfAbsent(v.category, () => []).add(v);
    }
    return map;
  }

  bool get isEmptyResult => featured == null && _visible.isEmpty;
}

class HelpCenterNotifier extends StateNotifier<HelpCenterState> {
  HelpCenterNotifier(this._repo) : super(const HelpCenterState());
  final HelpRepository _repo;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _repo.fetchVideos(limit: 100);
      List<String> cats = state.categories;
      if (cats.isEmpty) {
        try {
          cats = await _repo.fetchCategories();
        } catch (_) {
          // Non-fatal: fall back to categories derived from the videos.
          cats = page.items.map((v) => v.category).toSet().toList();
        }
      }
      state = state.copyWith(loading: false, all: page.items, categories: cats);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refresh() => load();

  void setSearch(String q) => state = state.copyWith(searchQuery: q);

  void setCategory(String? category) => state = state.copyWith(
        categoryFilter: category,
        clearCategory: category == null,
      );
}

final helpCenterProvider =
    StateNotifierProvider<HelpCenterNotifier, HelpCenterState>((ref) {
  return HelpCenterNotifier(ref.watch(helpRepositoryProvider));
});

// ── Video detail (with related) ───────────────────────────────────────────────

final helpVideoDetailProvider = FutureProvider.autoDispose
    .family<HelpVideoDetail, String>((ref, id) async {
  return ref.watch(helpRepositoryProvider).fetchVideo(id);
});

// ── Admin: management (all videos, any status) ────────────────────────────────

@immutable
class AdminHelpState {
  final bool loading;
  final String? error;
  final List<HelpVideoModel> all;
  final List<String> categories;

  const AdminHelpState({
    this.loading = false,
    this.error,
    this.all = const [],
    this.categories = const [],
  });

  AdminHelpState copyWith({
    bool? loading,
    String? error,
    List<HelpVideoModel>? all,
    List<String>? categories,
    bool clearError = false,
  }) {
    return AdminHelpState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      all: all ?? this.all,
      categories: categories ?? this.categories,
    );
  }
}

class AdminHelpNotifier extends StateNotifier<AdminHelpState> {
  AdminHelpNotifier(this._repo) : super(const AdminHelpState());
  final HelpRepository _repo;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _repo.fetchAdminVideos(limit: 100);
      List<String> cats = state.categories;
      if (cats.isEmpty) {
        try {
          cats = await _repo.fetchCategories();
        } catch (_) {
          cats = page.items.map((v) => v.category).toSet().toList();
        }
      }
      state = state.copyWith(loading: false, all: page.items, categories: cats);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> refresh() => load();

  Future<void> create({
    required String title,
    String? description,
    required String category,
    required String youtubeUrl,
    bool isActive = true,
    bool isFeatured = false,
  }) async {
    await _repo.createVideo(
      title: title,
      description: description,
      category: category,
      youtubeUrl: youtubeUrl,
      isActive: isActive,
      isFeatured: isFeatured,
    );
    await load();
  }

  Future<void> update(
    String id, {
    String? title,
    String? description,
    String? category,
    String? youtubeUrl,
    bool? isActive,
    bool? isFeatured,
  }) async {
    await _repo.updateVideo(
      id,
      title: title,
      description: description,
      category: category,
      youtubeUrl: youtubeUrl,
      isActive: isActive,
      isFeatured: isFeatured,
    );
    await load();
  }

  Future<void> setActive(String id, bool isActive) async {
    await _repo.setActive(id, isActive);
    await load();
  }

  Future<void> setFeatured(String id, bool isFeatured) async {
    await _repo.updateVideo(id, isFeatured: isFeatured);
    await load();
  }

  Future<void> delete(String id) async {
    await _repo.deleteVideo(id);
    await load();
  }

  Future<void> reorder(List<HelpVideoModel> ordered) async {
    await _repo.reorder(ordered);
    await load();
  }
}

final adminHelpProvider =
    StateNotifierProvider<AdminHelpNotifier, AdminHelpState>((ref) {
  return AdminHelpNotifier(ref.watch(helpRepositoryProvider));
});
