import 'package:flutter_test/flutter_test.dart';
import 'package:apx_pro/features/help_center/data/help_models.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  group('HelpVideoModel.extractYouTubeId', () {
    test('handles every common YouTube URL shape', () {
      final urls = [
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&t=42s',
        'https://m.youtube.com/watch?v=$id',
        'https://youtu.be/$id',
        'https://youtu.be/$id?si=share_junk',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube.com/live/$id',
        'youtube.com/watch?v=$id', // scheme-less
        id, // bare id
      ];
      for (final u in urls) {
        expect(HelpVideoModel.extractYouTubeId(u), id, reason: u);
      }
    });

    test('rejects invalid input', () {
      final bad = [
        'https://vimeo.com/12345678',
        'https://example.com/watch?v=$id',
        'https://www.youtube.com/watch',
        'not a url at all',
        'https://youtu.be/',
        'https://www.youtube.com/shorts/abc',
        '',
      ];
      for (final u in bad) {
        expect(HelpVideoModel.extractYouTubeId(u), isNull, reason: u);
      }
    });
  });

  group('HelpVideoModel.fromJson', () {
    test('parses a full backend payload', () {
      final json = {
        'id': 'abc-123',
        'title': 'How to Use APX PRO',
        'description': 'Complete introduction',
        'category': 'Getting Started',
        'youtube_url': 'https://youtube.com/watch?v=$id',
        'youtube_video_id': id,
        'display_order': 2,
        'is_active': true,
        'is_featured': true,
        'created_at': '2026-08-07T10:00:00+00:00',
        'updated_at': '2026-08-07T11:00:00+00:00',
        'thumbnail_url': 'https://img.youtube.com/vi/$id/hqdefault.jpg',
      };
      final v = HelpVideoModel.fromJson(json);
      expect(v.id, 'abc-123');
      expect(v.title, 'How to Use APX PRO');
      expect(v.category, 'Getting Started');
      expect(v.youtubeVideoId, id);
      expect(v.displayOrder, 2);
      expect(v.isActive, isTrue);
      expect(v.isFeatured, isTrue);
      expect(v.updatedAt, isNotNull);
      expect(v.thumbnail, contains('/vi/$id/'));
    });

    test('derives a thumbnail from the video id when none is provided', () {
      final v = HelpVideoModel.fromJson({
        'id': 'x',
        'title': 'T',
        'category': 'Other',
        'youtube_url': 'https://youtu.be/$id',
        'youtube_video_id': id,
        'display_order': 0,
        'is_active': true,
        'is_featured': false,
        'created_at': '2026-08-07T10:00:00+00:00',
      });
      expect(v.description, isNull);
      expect(v.updatedAt, isNull);
      expect(v.thumbnail, 'https://img.youtube.com/vi/$id/hqdefault.jpg');
    });
  });

  group('HelpVideoPage.fromJson', () {
    test('parses items and pagination', () {
      final page = HelpVideoPage.fromJson({
        'items': [
          {
            'id': '1',
            'title': 'A',
            'category': 'Other',
            'youtube_url': 'https://youtu.be/$id',
            'youtube_video_id': id,
            'display_order': 0,
            'is_active': true,
            'is_featured': false,
            'created_at': '2026-08-07T10:00:00+00:00',
          }
        ],
        'total': 1,
        'limit': 50,
        'offset': 0,
      });
      expect(page.items, hasLength(1));
      expect(page.total, 1);
      expect(page.limit, 50);
    });
  });

  group('HelpVideoDetail.fromJson', () {
    test('parses the video plus related list', () {
      Map<String, dynamic> vid(String i) => {
            'id': i,
            'title': 'V$i',
            'category': 'Rehabilitation',
            'youtube_url': 'https://youtu.be/$id',
            'youtube_video_id': id,
            'display_order': 0,
            'is_active': true,
            'is_featured': false,
            'created_at': '2026-08-07T10:00:00+00:00',
          };
      final detail = HelpVideoDetail.fromJson({
        'video': vid('1'),
        'related': [vid('2'), vid('3')],
      });
      expect(detail.video.id, '1');
      expect(detail.related, hasLength(2));
      expect(detail.related.first.id, '2');
    });
  });
}
