import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/torrent_player_models.dart';
import 'package:movie_app/utils/magnet_episode_parser.dart';

void main() {
  group('MagnetEpisodeParser', () {
    test('buildPlayRoute sorts SxxExx and builds magnet-file urls', () {
      final files = [
        const TorrentFileItem(
          index: 2,
          name: 'Show.S01E02.mkv',
          size: 900,
          isStreamable: true,
        ),
        const TorrentFileItem(
          index: 1,
          name: 'Show.S01E01.mkv',
          size: 800,
          isStreamable: true,
        ),
      ];

      final route =
          MagnetEpisodeParser.buildPlayRoute(files, routeName: 'Magnet');
      expect(route, isNotNull);
      expect(route!.episodes.length, 2);
      expect(route.episodes.first.name, 'S01E01');
      expect(route.episodes.first.url, 'magnet-file://1');
      expect(route.episodes.last.name, 'S01E02');
    });

    test('pickFileIndex prefers episode index over largest file', () {
      final files = [
        const TorrentFileItem(
          index: 0,
          name: 'Show.S01E01.mkv',
          size: 500,
          isStreamable: true,
        ),
        const TorrentFileItem(
          index: 1,
          name: 'Show.S01E02.mkv',
          size: 900,
          isStreamable: true,
        ),
      ];

      expect(
        MagnetEpisodeParser.pickFileIndex(files, episodeIndex: 1),
        1,
      );
    });

    test('pickFileIndex matches SxxExx in torrent title', () {
      final files = [
        const TorrentFileItem(
          index: 3,
          name: 'folder/Show.S02E05.720p.mkv',
          size: 700,
          isStreamable: true,
        ),
      ];

      expect(
        MagnetEpisodeParser.pickFileIndex(
          files,
          torrentTitle: 'Show S02E05 720p',
        ),
        3,
      );
    });

    test('buildPlayRoute returns null for single video', () {
      final files = [
        const TorrentFileItem(
          index: 0,
          name: 'movie.mkv',
          size: 1000,
          isStreamable: true,
        ),
      ];
      expect(
        MagnetEpisodeParser.buildPlayRoute(files, routeName: 'Magnet'),
        isNull,
      );
    });
  });
}
