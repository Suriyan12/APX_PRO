import 'package:flutter/foundation.dart';

/// A single Help Center instructional video, mirroring the backend
/// HelpVideoResponse. Only a YouTube URL + extracted id are stored — no files.
@immutable
class HelpVideoModel {
  final String id;
  final String title;
  final String? description;
  final String category;
  final String youtubeUrl;
  final String youtubeVideoId;
  final int displayOrder;
  final bool isActive;
  final bool isFeatured;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? thumbnailUrl;

  const HelpVideoModel({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    required this.youtubeUrl,
    required this.youtubeVideoId,
    required this.displayOrder,
    required this.isActive,
    required this.isFeatured,
    required this.createdAt,
    this.updatedAt,
    this.thumbnailUrl,
  });

  static DateTime _parseUtc(String iso) => DateTime.parse(iso).toLocal();

  factory HelpVideoModel.fromJson(Map<String, dynamic> j) {
    return HelpVideoModel(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      description: j['description'] as String?,
      category: j['category'] as String? ?? 'Other',
      youtubeUrl: j['youtube_url'] as String? ?? '',
      youtubeVideoId: j['youtube_video_id'] as String? ?? '',
      displayOrder: (j['display_order'] as num?)?.toInt() ?? 0,
      isActive: j['is_active'] as bool? ?? true,
      isFeatured: j['is_featured'] as bool? ?? false,
      createdAt: _parseUtc(j['created_at'] as String),
      updatedAt:
          j['updated_at'] != null ? _parseUtc(j['updated_at'] as String) : null,
      thumbnailUrl: j['thumbnail_url'] as String?,
    );
  }

  /// The best available thumbnail: the backend-provided URL, or a standard
  /// YouTube thumbnail derived from the video id.
  String? get thumbnail {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) return thumbnailUrl;
    if (youtubeVideoId.isNotEmpty) {
      return 'https://img.youtube.com/vi/$youtubeVideoId/hqdefault.jpg';
    }
    return null;
  }

  static final _ytIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Extract the 11-char YouTube video id from any common URL shape (or a bare
  /// id). Used to validate the admin's URL input before submitting.
  static String? extractYouTubeId(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return null;
    if (_ytIdPattern.hasMatch(raw)) return raw; // bare id
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null) return null;

    String? candidate;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be') {
      candidate = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if (host.endsWith('youtube.com') ||
        host.endsWith('youtube-nocookie.com')) {
      final segs = uri.pathSegments;
      if (uri.queryParameters['v'] != null) {
        candidate = uri.queryParameters['v'];
      } else if (segs.length >= 2 &&
          const {'shorts', 'embed', 'live', 'v'}.contains(segs.first)) {
        candidate = segs[1];
      }
    }
    if (candidate != null && _ytIdPattern.hasMatch(candidate)) return candidate;
    return null;
  }

  /// Payload for admin create/update. Only non-null fields are sent so the
  /// backend applies a partial update.
  Map<String, dynamic> toCreateJson() => {
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'category': category,
        'youtube_url': youtubeUrl,
        'display_order': displayOrder,
        'is_active': isActive,
        'is_featured': isFeatured,
      };
}

/// One page of help videos plus the total, for pagination.
@immutable
class HelpVideoPage {
  final List<HelpVideoModel> items;
  final int total;
  final int limit;
  final int offset;

  const HelpVideoPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory HelpVideoPage.fromJson(Map<String, dynamic> j) {
    final raw = j['items'] as List<dynamic>? ?? [];
    return HelpVideoPage(
      items: raw
          .map((e) => HelpVideoModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (j['total'] as num?)?.toInt() ?? 0,
      limit: (j['limit'] as num?)?.toInt() ?? raw.length,
      offset: (j['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single video plus related videos in the same category.
@immutable
class HelpVideoDetail {
  final HelpVideoModel video;
  final List<HelpVideoModel> related;

  const HelpVideoDetail({required this.video, this.related = const []});

  factory HelpVideoDetail.fromJson(Map<String, dynamic> j) {
    final rel = j['related'] as List<dynamic>? ?? [];
    return HelpVideoDetail(
      video: HelpVideoModel.fromJson(j['video'] as Map<String, dynamic>),
      related: rel
          .map((e) => HelpVideoModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
