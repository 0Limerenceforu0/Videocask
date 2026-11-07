import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/douban_lookup_service.dart';
import 'package:movie_app/services/tmdb_lookup_service.dart';

void main() {
  group('DoubanLookupService.parseSuggestItem', () {
    test('extracts English sub_title and year', () {
      final item = DoubanLookupService.parseSuggestItem({
        'title': '流浪地球',
        'sub_title': 'The Wandering Earth',
        'year': '2019',
        'id': '26266893',
        'type': 'movie',
      });
      expect(item?.englishTitle, 'The Wandering Earth');
      expect(item?.year, '2019');
      expect(item?.title, '流浪地球');
    });
  });

  group('TmdbLookupService.parseSearchResult', () {
    test('movie prefers original_title for English', () {
      final item = TmdbLookupService.parseSearchResult({
        'media_type': 'movie',
        'id': 693134,
        'title': '沙丘2',
        'original_title': 'Dune: Part Two',
        'release_date': '2024-03-01',
        'popularity': 120.5,
      });
      expect(item?.englishTitle, 'Dune: Part Two');
      expect(item?.year, '2024');
      expect(item?.mediaType, 'movie');
    });

    test('tv uses original_name', () {
      final item = TmdbLookupService.parseSearchResult({
        'media_type': 'tv',
        'id': 1399,
        'name': '权力的游戏',
        'original_name': 'Game of Thrones',
        'first_air_date': '2011-04-17',
        'popularity': 200,
      });
      expect(item?.englishTitle, 'Game of Thrones');
      expect(item?.year, '2011');
    });

    test('skips non video media types', () {
      expect(
        TmdbLookupService.parseSearchResult({
          'media_type': 'person',
          'id': 1,
          'name': 'Someone',
        }),
        isNull,
      );
    });
  });

  group('TmdbLookupService.parseDetailEnrichment', () {
    test('maps overview cast and similar', () {
      final detail = TmdbLookupService.parseDetailEnrichment(
        {
          'title': '流浪地球2',
          'original_title': 'The Wandering Earth II',
          'overview': '太阳危机',
          'poster_path': '/p.jpg',
          'backdrop_path': '/b.jpg',
          'vote_average': 8.2,
          'release_date': '2023-01-22',
          'genres': [
            {'name': '科幻'},
          ],
          'production_countries': [
            {'name': '中国大陆'},
          ],
          'credits': {
            'crew': [
              {'job': 'Director', 'name': '郭帆'},
            ],
            'cast': [
              {'name': '吴京'},
              {'name': '刘德华'},
            ],
          },
        },
        mediaType: 'movie',
        related: const [
          TmdbSimilarItem(
            tmdbId: 1,
            mediaType: 'movie',
            title: '流浪地球',
            year: '2019',
            posterUrl: 'https://example/p.jpg',
          ),
        ],
      );
      expect(detail?.displayTitle, '流浪地球2');
      expect(detail?.englishTitle, 'The Wandering Earth II');
      expect(detail?.director, '郭帆');
      expect(detail?.actors, ['吴京', '刘德华']);
      expect(detail?.related.length, 1);
    });
  });
}
