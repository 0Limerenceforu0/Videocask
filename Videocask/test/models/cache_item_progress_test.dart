import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/cache_item.dart';

void main() {
  group('CacheItem progress display', () {
    test('progressSizeLabel uses downloaded over total bytes', () {
      final item = CacheItem(
        id: '1',
        movieId: 'm',
        movieName: 'n',
        url: 'https://cdn/a.m3u8',
        fileSize: 800 * 1024 * 1024,
        downloadedSize: 400 * 1024 * 1024,
        status: 'downloading',
      );
      expect(item.progressSizeLabel, '400.0 MB / 800.0 MB');
      expect(item.showsDownloadProgress, isTrue);
    });

    test('progressSizeLabel works for m3u8 byte estimate', () {
      final item = CacheItem(
        id: '1',
        movieId: 'm',
        movieName: 'n',
        url: 'https://cdn/a.m3u8',
        fileSize: 200 * 1024 * 1024,
        downloadedSize: 106 * 1024 * 1024,
        status: 'downloading',
      );
      expect(item.progressSizeLabel, contains('/'));
      expect(item.progressSizeLabel, isNot(contains('%')));
    });
  });
}
