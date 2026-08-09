import 'package:apx_pro/core/network/api_client.dart';
import 'package:apx_pro/features/help_center/data/help_models.dart';

/// Talks to the Help Center backend (/help-videos). User methods fetch active
/// videos; admin methods manage the full library.
class HelpRepository {
  final ApiClient _api;
  HelpRepository(this._api);

  static const _base = '/help-videos';

  // ── User (read-only, active videos) ────────────────────────────────────────

  Future<HelpVideoPage> fetchVideos({
    String? category,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final r = await _api.get(_base, queryParameters: {
      'limit': limit,
      'offset': offset,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    });
    return HelpVideoPage.fromJson(r.data as Map<String, dynamic>);
  }

  Future<HelpVideoDetail> fetchVideo(String id) async {
    final r = await _api.get('$_base/$id');
    return HelpVideoDetail.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<String>> fetchCategories() async {
    final r = await _api.get('$_base/categories');
    return ((r.data as Map<String, dynamic>)['categories'] as List<dynamic>)
        .map((e) => e as String)
        .toList();
  }

  // ── Admin (management) ──────────────────────────────────────────────────────

  Future<HelpVideoPage> fetchAdminVideos({
    String? category,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final r = await _api.get('$_base/admin', queryParameters: {
      'limit': limit,
      'offset': offset,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    });
    return HelpVideoPage.fromJson(r.data as Map<String, dynamic>);
  }

  Future<HelpVideoModel> createVideo({
    required String title,
    String? description,
    required String category,
    required String youtubeUrl,
    int? displayOrder,
    bool isActive = true,
    bool isFeatured = false,
  }) async {
    final r = await _api.post(_base, data: {
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'category': category,
      'youtube_url': youtubeUrl,
      if (displayOrder != null) 'display_order': displayOrder,
      'is_active': isActive,
      'is_featured': isFeatured,
    });
    return HelpVideoModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<HelpVideoModel> updateVideo(
    String id, {
    String? title,
    String? description,
    String? category,
    String? youtubeUrl,
    int? displayOrder,
    bool? isActive,
    bool? isFeatured,
  }) async {
    final r = await _api.put('$_base/$id', data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (youtubeUrl != null) 'youtube_url': youtubeUrl,
      if (displayOrder != null) 'display_order': displayOrder,
      if (isActive != null) 'is_active': isActive,
      if (isFeatured != null) 'is_featured': isFeatured,
    });
    return HelpVideoModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<HelpVideoModel> setActive(String id, bool isActive) async {
    final r = await _api.patch('$_base/$id/active', data: {'is_active': isActive});
    return HelpVideoModel.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteVideo(String id) async {
    await _api.delete('$_base/$id');
  }

  Future<void> reorder(List<HelpVideoModel> orderedActiveList) async {
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < orderedActiveList.length; i++) {
      items.add({'id': orderedActiveList[i].id, 'display_order': i});
    }
    await _api.put('$_base/reorder', data: {'items': items});
  }
}
