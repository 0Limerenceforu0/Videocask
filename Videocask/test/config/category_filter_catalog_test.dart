import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/config/category_filter_catalog.dart';

void main() {
  group('CategoryFilterCatalog', () {
    test('each category has distinct genre lists', () {
      final movie = CategoryFilterCatalog.genresFor('电影');
      final tv = CategoryFilterCatalog.genresFor('剧集');
      final anime = CategoryFilterCatalog.genresFor('动漫');
      final variety = CategoryFilterCatalog.genresFor('综艺');
      final doc = CategoryFilterCatalog.genresFor('纪录片');

      expect(movie.first, '全部');
      expect(tv.first, '全部');
      expect(anime, isNot(equals(movie)));
      expect(variety, isNot(equals(movie)));
      expect(doc, isNot(equals(movie)));
      expect(anime, contains('热血'));
      expect(tv, contains('古装'));
      expect(variety, contains('真人秀'));
      expect(doc, contains('自然'));
    });

    test('each category has distinct region lists', () {
      final movie = CategoryFilterCatalog.regionsFor('电影');
      final anime = CategoryFilterCatalog.regionsFor('动漫');

      expect(movie, contains('印度'));
      expect(anime.first, '全部');
      expect(anime[1], '日本');
      expect(anime, isNot(equals(movie)));
    });

    test('normalize falls back to 全部 when option missing', () {
      expect(
        CategoryFilterCatalog.normalizeGenre('动漫', '剧情'),
        '全部',
      );
      expect(
        CategoryFilterCatalog.normalizeRegion('动漫', '印度'),
        '全部',
      );
      expect(
        CategoryFilterCatalog.normalizeGenre('电影', '剧情'),
        '剧情',
      );
    });
  });
}
