import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/local_media_http_server.dart';

void main() {
  group('parseM3u8ExtinfDurations', () {
    test('reads EXTINF values from playlist text', () {
      const content = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:4.004,
seg0.ts
#EXTINF:5.5,
seg1.ts
''';
      expect(parseM3u8ExtinfDurations(content), [4.004, 5.5]);
    });
  });

  group('normalizeM3u8SegmentDurations', () {
    test('pads missing durations with default 10s', () {
      expect(
        normalizeM3u8SegmentDurations([4.0], 3),
        [4.0, 10.0, 10.0],
      );
    });

    test('trims extra durations', () {
      expect(
        normalizeM3u8SegmentDurations([1.0, 2.0, 3.0], 2),
        [1.0, 2.0],
      );
    });
  });
}
