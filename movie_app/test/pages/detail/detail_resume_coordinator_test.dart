import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/watch_history.dart';
import 'package:movie_app/pages/detail/detail_player.dart';
import 'package:movie_app/pages/detail/detail_resume_coordinator.dart';

void main() {
  group('DetailResumeCoordinator', () {
    test('applyHistory restores route episode and pending resume', () {
      final player = DetailPlayer();
      final movie = Movie(
        id: '1',
        name: 'Test',
        playRoutes: [
          PlayRoute(
            name: 'HD',
            episodes: [
              Episode(index: 0, name: '1', url: 'u1'),
              Episode(index: 1, name: '2', url: 'u2'),
            ],
          ),
        ],
      );
      final history = WatchHistory(
        id: 's_1',
        movieId: '1',
        sourceId: 's',
        movieName: 'Test',
        episodeIndex: 1,
        routeIndex: 0,
        progress: 120000,
        duration: 3600000,
      );

      final applied = DetailResumeCoordinator.applyHistory(
        history,
        movie,
        player,
        0,
      );

      expect(applied.desktopRouteIndex, 0);
      expect(player.resumeTargetEpisodeIndex, 1);
      expect(
        player.pendingResumePosition,
        const Duration(milliseconds: 120000),
      );
    });

    test('episodeIndexForResume uses history target on matching route', () {
      final player = DetailPlayer()
        ..resumeTargetRouteIndex = 0
        ..resumeTargetEpisodeIndex = 2;
      final movie = Movie(
        id: '1',
        name: 'Test',
        playRoutes: [
          PlayRoute(
            name: 'HD',
            episodes: [
              Episode(index: 0, name: '1', url: 'u1'),
              Episode(index: 1, name: '2', url: 'u2'),
              Episode(index: 2, name: '3', url: 'u3'),
            ],
          ),
        ],
      );

      expect(
        DetailResumeCoordinator.episodeIndexForResume(movie, 0, player),
        2,
      );
      expect(
        DetailResumeCoordinator.episodeIndexForResume(movie, 0, player),
        isNot(0),
      );
    });

    test('applyHistory matches episode by saved name when index drifts', () {
      final player = DetailPlayer();
      final movie = Movie(
        id: '1',
        name: 'Variety',
        playRoutes: [
          PlayRoute(
            name: 'HD',
            episodes: [
              Episode(index: 0, name: '20240501期', url: 'u0'),
              Episode(index: 1, name: '20240508期', url: 'u1'),
              Episode(index: 2, name: '20240515期', url: 'u2'),
            ],
          ),
        ],
      );
      final history = WatchHistory(
        id: 's_1',
        movieId: '1',
        sourceId: 's',
        movieName: 'Variety',
        episodeIndex: 99,
        episodeName: '20240508期',
        routeIndex: 0,
        progress: 60000,
        duration: 3600000,
      );

      DetailResumeCoordinator.applyHistory(history, movie, player, 0);

      expect(player.resumeTargetEpisodeIndex, 1);
      expect(player.pendingResumePosition, const Duration(milliseconds: 60000));
    });
  });
}
