import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/cache_item.dart';
import 'package:movie_app/utils/cache_playback_helper.dart';

void main() {
  group('CachePlaybackHelper', () {
    test('movieFromCacheItem maps fields', () {
      final item = CacheItem(
        id: 'c1',
        movieId: 'm1',
        sourceId: 'src_a',
        movieName: 'Test Movie',
        movieCover: 'https://example.com/p.jpg',
        episodeIndex: 2,
        episodeName: '第3集',
        url: 'https://cdn.example.com/a.mp4',
      );
      final movie = CachePlaybackHelper.movieFromCacheItem(item);
      expect(movie.id, 'm1');
      expect(movie.sourceId, 'src_a');
      expect(movie.name, 'Test Movie');
      expect(movie.cover, 'https://example.com/p.jpg');
      expect(movie.updateStatus, '第3集');
    });
  });
}
