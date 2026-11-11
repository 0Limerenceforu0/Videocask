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

  group('DoubanLookupService 年份硬约束', () {
    // 2026-11-11 真机根因：`Hi Mom`（2021）在豆瓣联想里撞到 1970 年的同名短片
    // `Hi, Mom!`，旧打分靠分词命中（40+40）+ 基础分拿到 145 分过了 80 门槛，
    // 于是 `豆瓣解析: Hi Mom -> Hi, Mom! (1970)`，错片条目被塞进磁力详情补全。
    const hiMom1970 = DoubanSuggestMatch(
      title: '嗨，妈妈！',
      englishTitle: 'Hi, Mom!',
      year: '1970',
      doubanId: '1292susp',
      type: 'movie',
    );
    const hiMom2021 = DoubanSuggestMatch(
      title: '你好，李焕英',
      englishTitle: 'Hi, Mom',
      year: '2021',
      doubanId: '34841067',
      type: 'movie',
    );

    test('年份明确不一致时直接判 0 分（不会过 80 门槛）', () {
      final s = DoubanLookupService.scoreMatchForTest(
        hiMom1970,
        'Hi Mom',
        '2021',
      );
      expect(s, 0);
      expect(s, lessThan(80));
    });

    test('同年候选仍能正常过门槛，且分数高于错年候选', () {
      final right = DoubanLookupService.scoreMatchForTest(
        hiMom2021,
        'Hi Mom',
        '2021',
      );
      final wrong = DoubanLookupService.scoreMatchForTest(
        hiMom1970,
        'Hi Mom',
        '2021',
      );
      expect(right, greaterThanOrEqualTo(80));
      expect(right, greaterThan(wrong));
    });

    test('候选年份缺失时不做否决（避免误杀豆瓣剧集）', () {
      const noYear = DoubanSuggestMatch(
        title: '你好，李焕英',
        englishTitle: 'Hi, Mom',
        year: '',
        doubanId: '34841067',
        type: 'movie',
      );
      final s = DoubanLookupService.scoreMatchForTest(
        noYear,
        'Hi Mom',
        '2021',
      );
      expect(s, greaterThanOrEqualTo(80));
    });

    test('年份提示缺失时保持旧行为（不做否决）', () {
      final s = DoubanLookupService.scoreMatchForTest(
        hiMom1970,
        'Hi Mom',
        null,
      );
      expect(s, greaterThanOrEqualTo(80));
    });

    test('区间年份不参与否决', () {
      final s = DoubanLookupService.scoreMatchForTest(
        hiMom1970,
        'Hi Mom',
        '2021-2022',
      );
      expect(s, greaterThan(0));
    });

    test('相差 1 年不否决（豆瓣 year 是上映年，可能差 1）', () {
      const almost = DoubanSuggestMatch(
        title: '你好，李焕英',
        englishTitle: 'Hi, Mom',
        year: '2020',
        doubanId: '34841067',
        type: 'movie',
      );
      final s = DoubanLookupService.scoreMatchForTest(
        almost,
        'Hi Mom',
        '2021',
      );
      expect(s, greaterThanOrEqualTo(80));
    });
  });
}
