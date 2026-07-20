import 'package:flutter_test/flutter_test.dart';
import 'package:apx_pro/features/rehab/data/rehab_models.dart';

void main() {
  group('extractYouTubeId', () {
    const id = 'dQw4w9WgXcQ';

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
        'https://www.youtube-nocookie.com/embed/$id',
        id, // bare video id
      ];
      for (final u in urls) {
        expect(RehabExerciseModel.extractYouTubeId(u), id, reason: u);
      }
    });

    test('rejects invalid input', () {
      final bad = [
        'https://vimeo.com/12345678',
        'https://example.com/watch?v=$id',   // not a YouTube host
        'https://www.youtube.com/watch',      // no v param
        'not a url at all',
        'https://youtu.be/',                  // no id
        'https://www.youtube.com/shorts/abc', // id too short
        '',
      ];
      for (final u in bad) {
        expect(RehabExerciseModel.extractYouTubeId(u), isNull, reason: u);
      }
    });
  });
}
