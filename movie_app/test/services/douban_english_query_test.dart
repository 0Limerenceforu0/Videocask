import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/douban_lookup_service.dart';

void main() {
  group('DoubanLookupService 英文查询打分', () {
    // 豆瓣联想接口对英文片名同样返回结果，且 title 字段是中文片名
    // （实测 q=Shawshank → title: 肖申克的救赎 / sub_title: The Shawshank Redemption）。
    // 打分必须拿「英文查询比英文副标题」，否则英文查询恒判不相关 → 返回 null。
    final shawshank = DoubanSuggestMatch(
      title: '肖申克的救赎',
      englishTitle: 'The Shawshank Redemption',
      year: '1994',
      doubanId: '1292052',
      type: 'movie',
    );
    final godfather = DoubanSuggestMatch(
      title: '教父',
      englishTitle: 'The Godfather',
      year: '1972',
      doubanId: '1291841',
      type: 'movie',
    );

    test('英文查询比英文副标题时得分高', () {
      final s = DoubanLookupService.scoreMatchForTest(
        shawshank,
        'The Shawshank Redemption',
        null,
      );
      final g = DoubanLookupService.scoreMatchForTest(
        godfather,
        'The Shawshank Redemption',
        null,
      );
      expect(s, greaterThan(g));
      // 达到 suggest 的 80 分门槛 → 会被采纳。
      expect(s, greaterThanOrEqualTo(80));
    });

    test('英文查询命中副标题子串也能过门槛', () {
      final s = DoubanLookupService.scoreMatchForTest(
        shawshank,
        'Shawshank',
        null,
      );
      expect(s, greaterThanOrEqualTo(80));
    });

    test('年份一致额外加分', () {
      final withYear = DoubanLookupService.scoreMatchForTest(
        shawshank,
        'Shawshank',
        '1994',
      );
      final withoutYear = DoubanLookupService.scoreMatchForTest(
        shawshank,
        'Shawshank',
        null,
      );
      expect(withYear, greaterThan(withoutYear));
    });

    test('中文查询仍按中文名打分（老行为不变）', () {
      final s = DoubanLookupService.scoreMatchForTest(
        shawshank,
        '肖申克的救赎',
        null,
      );
      expect(s, greaterThanOrEqualTo(80));
    });

    test('完全无关的查询得分很低', () {
      final s = DoubanLookupService.scoreMatchForTest(
        shawshank,
        '完全不相关的片子名',
        null,
      );
      expect(s, lessThan(80));
    });
  });
}
