import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/cache_episode_status.dart';
import 'package:movie_app/models/cache_item.dart';
import 'package:movie_app/providers/cache_provider.dart';

void main() {
  group('CacheProvider.episodeCacheStatus', () {
    test('returns none when no tasks', () {
      final provider = CacheProvider();
      expect(
        provider.episodeCacheStatus(movieId: 'x', episodeIndex: 0),
        CacheEpisodeStatus.none,
      );
    });
  });

  group('CacheEpisodeStatus mapping from CacheItem.status', () {
    test('failed tasks show as paused in episode picker', () {
      expect(
          CacheItem(
            id: '1',
            movieId: 'm',
            movieName: 'n',
            url: 'u',
            status: 'failed',
          ).isFailed,
          isTrue);

      final provider = CacheProvider();
      expect(
        provider.episodeCacheStatus(movieId: 'missing', episodeIndex: 0),
        CacheEpisodeStatus.none,
      );
    });
  });

  group('CacheEpisodeStatusX', () {
    test('isActive covers waiting downloading paused', () {
      expect(CacheEpisodeStatus.waiting.isActive, isTrue);
      expect(CacheEpisodeStatus.downloading.isActive, isTrue);
      expect(CacheEpisodeStatus.paused.isActive, isTrue);
      expect(CacheEpisodeStatus.completed.isActive, isFalse);
      expect(CacheEpisodeStatus.none.isActive, isFalse);
    });
  });
}
