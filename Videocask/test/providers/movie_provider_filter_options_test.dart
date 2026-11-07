import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/providers/movie_provider.dart';

/// 动态筛选词表的 provider 层行为（2026-10-21）。
///
/// 契约：
/// - 源有类型元数据时，候选词来自**源真实标注**，不再用与源脱节的静态词表；
/// - 源完全没有元数据时，回退静态词表（至少给出可选项）；
/// - 已选词若不在当前可用词表里，必须回退到「全部」，否则 UI 与筛选条件错位。
void main() {
  group('MovieProvider 动态筛选词表', () {
    test('无数据时回退静态词表（不出现空筛选栏）', () {
      final provider = MovieProvider();

      expect(provider.categoryFilterOptions.genres, isEmpty);
      expect(provider.categoryHasFilterMetadata, isFalse);
      // 静态词表仍以「全部」开头。
      expect(provider.categoryGenreOptions.first, '全部');
      expect(provider.categoryRegionOptions.first, '全部');
    });

    test('已选词不在可用词表时归一回「全部」', () {
      final provider = MovieProvider();

      final normalized = provider.normalizeSelectedFilters(
        genre: '热血',
        region: '火星',
      );

      // 未加载任何类目时用的是电影静态词表；「热血」属动漫词表 → 回退。
      expect(normalized.genre, '全部');
      // 「火星」不在任何词表 → 回退。
      expect(normalized.region, '全部');
    });

    test('地区词在静态词表内时保留', () {
      final provider = MovieProvider();

      final normalized = provider.normalizeSelectedFilters(
        genre: '全部',
        region: '中国大陆',
      );

      expect(normalized.region, '中国大陆');
    });

    test('类型词在当前词表内时保留', () {
      final provider = MovieProvider();

      // 「动作」在电影静态词表内 → 保留。
      final normalized = provider.normalizeSelectedFilters(
        genre: '动作',
        region: '全部',
      );

      expect(normalized.genre, '动作');
    });
  });

  group('MovieProvider 首页分区派生', () {
    test('无分类数据时派生结果为空（不崩、不留脏数据）', () {
      final provider = MovieProvider();

      provider.deriveHomeSectionsFromCategory();

      expect(provider.bannerList, isEmpty);
      expect(provider.topRatedMovies, isEmpty);
    });
  });
}
