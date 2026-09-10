import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/l10n/app_localizations.dart';
import 'package:movie_app/l10n/app_localizations_zh.dart';
import 'package:movie_app/models/cache_item.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/pages/detail/episode_download_coordinator.dart';
import 'package:movie_app/services/cache_service.dart';

Movie _movieWithEpisodes(List<Episode> episodes) {
  return Movie(
    id: 'm1',
    name: 'Test',
    playRoutes: [
      PlayRoute(name: 'HD', episodes: episodes),
    ],
  );
}

void main() {
  group('EpisodeDownloadCoordinator.preflightSkipReason', () {
    test('magnet detail is blocked', () {
      final movie = _movieWithEpisodes([
        Episode(index: 0, name: '1', url: 'https://v.example.com/play/a'),
      ]);
      expect(
        EpisodeDownloadCoordinator.preflightSkipReason(
          isMagnetDetail: true,
          movie: movie,
          routeIndex: 0,
          episodeIndex: 0,
        ),
        EpisodeDownloadSkipReason.magnetUnsupported,
      );
    });

    test('empty play routes', () {
      final movie = Movie(id: 'm1', name: 'Test');
      expect(
        EpisodeDownloadCoordinator.preflightSkipReason(
          isMagnetDetail: false,
          movie: movie,
          routeIndex: 0,
          episodeIndex: 0,
        ),
        EpisodeDownloadSkipReason.noEpisode,
      );
    });

    test('invalid episode index', () {
      final movie = _movieWithEpisodes([
        Episode(index: 0, name: '1', url: 'https://cdn/a.mp4'),
      ]);
      expect(
        EpisodeDownloadCoordinator.preflightSkipReason(
          isMagnetDetail: false,
          movie: movie,
          routeIndex: 0,
          episodeIndex: 3,
        ),
        EpisodeDownloadSkipReason.noEpisode,
      );
      expect(
        EpisodeDownloadCoordinator.preflightSkipReason(
          isMagnetDetail: false,
          movie: movie,
          routeIndex: 0,
          episodeIndex: -1,
        ),
        EpisodeDownloadSkipReason.noEpisode,
      );
    });

    test('empty episode url', () {
      final movie = _movieWithEpisodes([
        Episode(index: 0, name: '1', url: '  '),
      ]);
      expect(
        EpisodeDownloadCoordinator.preflightSkipReason(
          isMagnetDetail: false,
          movie: movie,
          routeIndex: 0,
          episodeIndex: 0,
        ),
        EpisodeDownloadSkipReason.noEpisode,
      );
    });

    test('valid cms episode passes preflight', () {
      final movie = _movieWithEpisodes([
        Episode(index: 0, name: '1', url: 'https://v.example.com/play/a'),
      ]);
      expect(
        EpisodeDownloadCoordinator.preflightSkipReason(
          isMagnetDetail: false,
          movie: movie,
          routeIndex: 0,
          episodeIndex: 0,
        ),
        isNull,
      );
    });
  });

  group('EpisodeDownloadCoordinator.outcomeForExistingTask', () {
    CacheItem task(String status) {
      return CacheItem(
        id: 'c1',
        movieId: 'm1',
        movieName: 'T',
        url: 'https://cdn/a.mp4',
        status: status,
      );
    }

    test('maps cache statuses to download outcomes', () {
      expect(
        EpisodeDownloadCoordinator.outcomeForExistingTask(task('completed')),
        EpisodeDownloadOutcome.alreadyCompleted,
      );
      expect(
        EpisodeDownloadCoordinator.outcomeForExistingTask(task('downloading')),
        EpisodeDownloadOutcome.alreadyActive,
      );
      expect(
        EpisodeDownloadCoordinator.outcomeForExistingTask(task('waiting')),
        EpisodeDownloadOutcome.alreadyActive,
      );
      expect(
        EpisodeDownloadCoordinator.outcomeForExistingTask(task('paused')),
        EpisodeDownloadOutcome.resumed,
      );
      expect(
        EpisodeDownloadCoordinator.outcomeForExistingTask(task('failed')),
        EpisodeDownloadOutcome.resumed,
      );
      expect(
        EpisodeDownloadCoordinator.outcomeForExistingTask(null),
        isNull,
      );
    });
  });

  group('EpisodeDownloadCoordinator.validateResolvedUrl', () {
    const page = 'https://v.example.com/play/abc';

    test('parse failure when still a play page', () {
      expect(
        EpisodeDownloadCoordinator.validateResolvedUrl(
          episodePageUrl: page,
          downloadUrl: page,
        ),
        EpisodeDownloadSkipReason.parseFailed,
      );
    });

    test('resolved m3u8 is acceptable', () {
      expect(
        EpisodeDownloadCoordinator.validateResolvedUrl(
          episodePageUrl: page,
          downloadUrl: 'https://cdn.example.com/hls/index.m3u8',
        ),
        isNull,
      );
    });

    test('direct mp4 without parse is acceptable', () {
      expect(
        EpisodeDownloadCoordinator.validateResolvedUrl(
          episodePageUrl: 'https://cdn.example.com/a.mp4',
          downloadUrl: 'https://cdn.example.com/a.mp4',
        ),
        isNull,
      );
    });

    test('rejects magnet and file schemes', () {
      expect(
        EpisodeDownloadCoordinator.validateResolvedUrl(
          episodePageUrl: page,
          downloadUrl: 'magnet:?xt=urn:btih:abc',
        ),
        EpisodeDownloadSkipReason.unsupportedUrl,
      );
      expect(
        EpisodeDownloadCoordinator.validateResolvedUrl(
          episodePageUrl: page,
          downloadUrl: 'file:///data/a.mp4',
        ),
        EpisodeDownloadSkipReason.unsupportedUrl,
      );
    });

    test('rejects non-http urls', () {
      expect(
        EpisodeDownloadCoordinator.validateResolvedUrl(
          episodePageUrl: page,
          downloadUrl: 'rtmp://live.example.com/stream',
        ),
        EpisodeDownloadSkipReason.unsupportedUrl,
      );
    });
  });

  group('EpisodeDownloadCoordinator.countBatchAdded', () {
    test('counts queued and resumed only', () {
      expect(
        EpisodeDownloadCoordinator.countBatchAdded(const [
          EpisodeDownloadOutcome.queued,
          EpisodeDownloadOutcome.alreadyCompleted,
          EpisodeDownloadOutcome.resumed,
          EpisodeDownloadOutcome.skipped,
          EpisodeDownloadOutcome.alreadyActive,
        ]),
        2,
      );
      expect(
        EpisodeDownloadCoordinator.countBatchAdded(const []),
        0,
      );
    });
  });

  group('EpisodeDownloadCoordinator.isEpisodeSelectableForBatch', () {
    test('completed or empty url episodes are not selectable', () {
      expect(
        EpisodeDownloadCoordinator.isEpisodeSelectableForBatch(
          episodeUrl: 'https://a.mp4',
          cacheCompleted: true,
        ),
        isFalse,
      );
      expect(
        EpisodeDownloadCoordinator.isEpisodeSelectableForBatch(
          episodeUrl: '',
          cacheCompleted: false,
        ),
        isFalse,
      );
      expect(
        EpisodeDownloadCoordinator.isEpisodeSelectableForBatch(
          episodeUrl: 'https://a.mp4',
          cacheCompleted: false,
        ),
        isTrue,
      );
    });
  });

  group('EpisodeDownloadCoordinator.skipMessage', () {
    test('maps all skip reasons to non-empty l10n', () {
      final l10n = AppLocalizationsZh();
      for (final reason in EpisodeDownloadSkipReason.values) {
        final message = EpisodeDownloadCoordinator.skipMessage(l10n, reason);
        expect(message, isNotEmpty);
      }
    });
  });

  group('EpisodeDownloadCoordinator.fetchHeadersForItem', () {
    test('uses pageUrl as Referer for CDN requests', () {
      final item = CacheItem(
        id: 'c1',
        movieId: 'm1',
        movieName: 'T',
        url: 'https://cdn.example.com/seg.ts',
        pageUrl: 'https://v.example.com/play/abc',
      );
      final headers = EpisodeDownloadCoordinator.fetchHeadersForItem(item);
      expect(headers['Referer'], 'https://v.example.com/play/abc/');
      expect(headers['Origin'], 'https://v.example.com');
    });
  });

  group('EpisodeDownloadCoordinator.isValidDownloadedVideoSize', () {
    test('rejects tiny files', () {
      expect(
        EpisodeDownloadCoordinator.isValidDownloadedVideoSize(
          CacheService.minValidVideoBytes - 1,
        ),
        isFalse,
      );
      expect(
        EpisodeDownloadCoordinator.isValidDownloadedVideoSize(
          CacheService.minValidVideoBytes,
        ),
        isTrue,
      );
    });
  });
}
