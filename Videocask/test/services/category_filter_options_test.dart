import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/services/category_filter_options.dart';

/// 动态筛选词聚合（2026-10-21）。
///
/// 背景：静态词表写的是「热血/校园/百合」等二次元细分词，但采集站实际只标到
/// 「动画/动作/奇幻」这一层（实测 lzi `ac=detail&t=29`），选「热血」必然 0 命中。
/// 改为从**已加载条目的真实 `vod_class`** 聚合候选词，保证每个选项都有结果。
Movie _m(
  String id, {
  List<String> genreTags = const [],
  String region = '',
  List<String>? genres,
}) {
  return Movie(
    id: id,
    name: '影片$id',
    genreTags: genreTags,
    genres: genres ?? genreTags,
    region: region,
  );
}

void main() {
  group('aggregateFilterOptions', () {
test('从 vod_class 聚合类型词，按频次降序', () {
      final options = aggregateFilterOptions([
  _m('1', genreTags: ['动画', '奇幻']),
        _m('2', genreTags: ['动画']),
    _m('3', genreTags: ['动画', '动作']),
        _m('4', genreTags: ['剧情']),
      ]);

      // 动画 3 次居首；其余各 1 次，按码点升序（稳定排序，非拼音序）。
      expect(options.genres, ['动画', '剧情', '动作', '奇幻']);
    });

    test('频次相同时按码点升序，保证结果稳定', () {
      final options = aggregateFilterOptions([
    _m('1', genreTags: ['奇幻']),
        _m('2', genreTags: ['动作']),
   ]);

      expect(options.genres, ['动作', '奇幻']);
    });

    test('地区归一：「大陆」与「中国大陆」合并为一项', () {
      final options = aggregateFilterOptions([
        _m('1', region: '中国大陆'),
        _m('2', region: '大陆'),
        _m('3', region: '大陆'),
      ]);

      expect(options.regions, ['中国大陆']);
    });

    test('地区归一：香港/台湾/澳门', () {
      expect(normalizeRegionLabel('香港'), '中国香港');
      expect(normalizeRegionLabel('台湾'), '中国台湾');
      expect(normalizeRegionLabel('澳门'), '中国澳门');
      expect(normalizeRegionLabel('中国大陆'), '中国大陆');
      expect(normalizeRegionLabel('日本'), '日本');
      expect(normalizeRegionLabel('  '), '');
    });

    test('空输入返回空结果', () {
      final options = aggregateFilterOptions(const []);

      expect(options.genres, isEmpty);
      expect(options.regions, isEmpty);
      expect(options.hasMetadata, isFalse);
    });

    test('条目无类型信息时不产生空词条', () {
      final options = aggregateFilterOptions([
        _m('1', genreTags: ['', '  ']),
        _m('2', genreTags: []),
      ]);

      expect(options.genres, isEmpty);
    });

    test('数量上限生效，防止词条爆炸撑爆筛选栏', () {
      final movies = List.generate(
        30,
        (i) => _m('$i', genreTags: ['类型$i']),
      );

      final options = aggregateFilterOptions(movies, maxItems: 5);

      expect(options.genres.length, 5);
    });

    test('hasMetadata 反映是否拿到了真实元数据', () {
      expect(
        aggregateFilterOptions([_m('1', genreTags: ['动画'])]).hasMetadata,
        isTrue,
      );
      expect(
        aggregateFilterOptions([_m('1', region: '中国大陆')]).hasMetadata,
        isTrue,
      );
      expect(aggregateFilterOptions([_m('1')]).hasMetadata, isFalse);
    });

    test('真实数据形态：只标到「动画/动作/奇幻」这一层时不会产出「热血」', () {
      // 这正是线上源站的标注粒度 —— 静态词表里的「热血」根本不该出现。
      final options = aggregateFilterOptions([
        _m('1', genreTags: ['动画', '奇幻']),
        _m('2', genreTags: ['动画']),
        _m('3', genreTags: ['动作', '动画', '奇幻']),
        _m('4', genreTags: ['剧情', '动画', '历史']),
        _m('5', genreTags: ['喜剧', '动作', '动画', '奇幻', '古装']),
      ]);

      expect(options.genres, contains('动画'));
      expect(options.genres, contains('奇幻'));
      expect(options.genres, isNot(contains('热血')));
      expect(options.genres, isNot(contains('校园')));
    });
  });
}