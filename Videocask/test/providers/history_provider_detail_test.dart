import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/config/constants.dart';
import 'package:movie_app/models/watch_history.dart';
import 'package:movie_app/providers/history_provider.dart';

void main() {
  group('HistoryProvider.findHistoryForDetail', () {
    test('prefers exact source then falls back to most recent', () {
      final provider = HistoryProvider();
      provider.histories.addAll([
        WatchHistory(
          id: 'b_1',
          movieId: '1',
          sourceId: 'b',
          movieName: 'B',
          episodeIndex: 2,
          progress: 1000,
          duration: 5000,
          lastWatchTime: DateTime(2026, 1, 1),
        ),
        WatchHistory(
          id: 'a_1',
          movieId: '1',
          sourceId: 'a',
          movieName: 'A',
          episodeIndex: 5,
          progress: 2000,
          duration: 6000,
          lastWatchTime: DateTime(2026, 2, 1),
        ),
      ]);

      expect(
        provider
            .findHistoryForDetail(movieId: '1', sourceId: 'a')
            ?.episodeIndex,
        5,
      );
      expect(
        provider.findHistoryForDetail(movieId: '1', sourceId: 'z')?.sourceId,
        'b',
      );
    });

    test('matches magnet uri before generic source lookup', () {
      final provider = HistoryProvider();
      const magnet = 'magnet:?xt=urn:btih:abc';
      provider.histories.addAll([
        WatchHistory(
          id: '${AppConstants.magnetDetailSourceId}_x',
          movieId: 'x',
          sourceId: AppConstants.magnetDetailSourceId,
          movieName: 'Magnet',
          magnetUri: magnet,
          progress: 3000,
          duration: 9000,
        ),
      ]);

      final h = provider.findHistoryForDetail(
        movieId: 'x',
        magnetUri: magnet,
      );
      expect(h?.progress, 3000);
      expect(h?.magnetUri, magnet);
    });
  });

  group('HistoryProvider.saveOrUpdateHistory progress guard', () {
    test('does not overwrite meaningful progress with zero at open', () async {
      final provider = HistoryProvider();
      provider.histories.add(
        WatchHistory(
          id: 'a_1',
          movieId: '1',
          sourceId: 'a',
          movieName: 'Test',
          episodeIndex: 1,
          routeIndex: 0,
          progress: 600000,
          duration: 3600000,
          lastWatchTime: DateTime(2026, 1, 1),
        ),
      );

      await provider.saveOrUpdateHistory(
        movieId: '1',
        movieName: 'Test',
        movieCover: '',
        episodeIndex: 1,
        episodeName: '第2集',
        progress: 0,
        duration: 3600000,
        sourceId: 'a',
        routeIndex: 0,
      );

      expect(provider.histories.first.progress, 600000);
    });

    test('allows zero progress when episode changes', () async {
      final provider = HistoryProvider();
      provider.histories.add(
        WatchHistory(
          id: 'a_1',
          movieId: '1',
          sourceId: 'a',
          movieName: 'Test',
          episodeIndex: 1,
          routeIndex: 0,
          progress: 600000,
          duration: 3600000,
          lastWatchTime: DateTime(2026, 1, 1),
        ),
      );

      await provider.saveOrUpdateHistory(
        movieId: '1',
        movieName: 'Test',
        movieCover: '',
        episodeIndex: 2,
        episodeName: '第3集',
        progress: 0,
        duration: 3600000,
        sourceId: 'a',
        routeIndex: 0,
      );

      expect(provider.histories.first.episodeIndex, 2);
      expect(provider.histories.first.progress, 0);
    });

    test('updates progress when new value is meaningful', () async {
      final provider = HistoryProvider();
      provider.histories.add(
        WatchHistory(
          id: 'a_1',
          movieId: '1',
          sourceId: 'a',
          movieName: 'Test',
          episodeIndex: 0,
          routeIndex: 0,
          progress: 100000,
          duration: 3600000,
          lastWatchTime: DateTime(2026, 1, 1),
        ),
      );

      await provider.saveOrUpdateHistory(
        movieId: '1',
        movieName: 'Test',
        movieCover: '',
        episodeIndex: 0,
        episodeName: '第1集',
        progress: 900000,
        duration: 3600000,
        sourceId: 'a',
        routeIndex: 0,
      );

      expect(provider.histories.first.progress, 900000);
    });
  });
}
