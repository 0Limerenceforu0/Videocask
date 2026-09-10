import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/playback_url_resolver.dart';

void main() {
  group('PlaybackUrlResolver.needsWebParse', () {
    test('detects CMS play pages', () {
      expect(
        PlaybackUrlResolver.needsWebParse('https://v.example.com/play/abc'),
        isTrue,
      );
    });

    test('skips direct m3u8 and mp4', () {
      expect(
        PlaybackUrlResolver.needsWebParse(
          'https://cdn.example.com/a/index.m3u8',
        ),
        isFalse,
      );
      expect(
        PlaybackUrlResolver.needsWebParse('https://cdn.example.com/a.mp4'),
        isFalse,
      );
    });

    test('skips magnet links', () {
      expect(
        PlaybackUrlResolver.needsWebParse('magnet:?xt=urn:btih:abc'),
        isFalse,
      );
    });
  });
}
