import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/services/imdb_lookup_service.dart';

/// 2026-10-28 真机回归：搜「战狼」时整页磁力资源变成《Logan(金刚狼)》。
///
/// 实测数据（IMDb 联想接口对 `战狼` 的真实返回）：
///   tt3315342  Logan        y=2017  rank=1168   → 得分 401.28
///   tt3540136  Wolf Warrior y=2015  rank=48946  → 得分 258（含年份命中 +110）
/// 修复前按总分取最高 → 选中 Logan；修复后年份命中硬优先 → 选中 Wolf Warrior。
///
/// 负向验证：把 [ImdbLookupService.chooseId] 里的 `useYearHit` 改回只看
/// `bestScore`，第一组用例立刻变红。
void main() {
  group('IMDb 候选裁决：年份命中优先于全球热度', () {
    test('搜「战狼」应选 2015 的 Wolf Warrior，而不是热度更高的 Logan', () {
      final id = ImdbLookupService.chooseId(
        bestId: 'tt3315342', // Logan 2017，热度最高
        bestScore: 401.28,
        yearId: 'tt3540136', // Wolf Warrior 2015，年份命中
        yearScore: 258,
        threshold: 72,
      );
      expect(id, 'tt3540136');
    });

    test('年份命中侧未达阈值时退回热度最高者', () {
      final id = ImdbLookupService.chooseId(
        bestId: 'tt3315342',
        bestScore: 401.28,
        yearId: 'tt3540136',
        yearScore: 60, // < 72
        threshold: 72,
      );
      expect(id, 'tt3315342');
    });

    test('没有年份命中时退回热度最高者', () {
      final id = ImdbLookupService.chooseId(
        bestId: 'tt3315342',
        bestScore: 401.28,
        yearId: null,
        yearScore: 0,
        threshold: 72,
      );
      expect(id, 'tt3315342');
    });

    test('两侧都没有达阈值候选时返回 null（调用方回退片名搜索）', () {
      final id = ImdbLookupService.chooseId(
        bestId: 'tt3315342',
        bestScore: 40,
        yearId: null,
        yearScore: 0,
        threshold: 72,
      );
      expect(id, isNull);
    });

    test('补全路径阈值 65：年份命中同样优先', () {
      final id = ImdbLookupService.chooseId(
        bestId: 'tt3315342',
        bestScore: 300,
        yearId: 'tt3540136',
        yearScore: 70,
        threshold: 65,
      );
      expect(id, 'tt3540136');
    });
  });

  group('中文查询无年份命中：不接受「热度高但片名无关」的候选', () {
    // 真实接口分数（2026-10-28 实测 v2.sg.media-imdb.com/suggestion/x/我不是药神）：
    //   tt0970866 Little Fockers     y=2010 rank=3943  → 290.28（热度最高）
    //   tt7362036 Dying to Survive   y=2018 rank=24278 → 278.00（标题/年份正确）
    // 旧逻辑取热度最高 → 整页磁力资源变成《Little Fockers》。
    test('「我不是药神」的正确结果是 Dying to Survive，不是 Little Fockers', () {
      final id = ImdbLookupService.chooseCandidate(
        cjkQuery: true,
        bestId: 'tt0970866',
        bestScore: 290.28,
        labelMatchedId: null,
        labelMatchedScore: 0,
        yearId: 'tt7362036',
        yearScore: 278.00,
      );
      expect(id, 'tt7362036');
    });

    test('无年份线索时，中文查询宁可不解析也不猜热门片', () {
      final id = ImdbLookupService.chooseCandidate(
        cjkQuery: true,
        bestId: 'tt0970866',
        bestScore: 290.28,
        labelMatchedId: null,
        labelMatchedScore: 0,
        yearId: null,
        yearScore: 0,
      );
      expect(id, isNull);
    });

    test('无年份线索但标题真的对上时仍然采用', () {
      final id = ImdbLookupService.chooseCandidate(
        cjkQuery: true,
        bestId: 'tt0970866',
        bestScore: 290.28,
        labelMatchedId: 'tt7777777',
        labelMatchedScore: 150,
        yearId: null,
        yearScore: 0,
      );
      expect(id, 'tt7777777');
    });

    test('非中文查询保持原规则：无年份线索取热度最高', () {
      final id = ImdbLookupService.chooseCandidate(
        cjkQuery: false,
        bestId: 'tt0970866',
        bestScore: 290.28,
        labelMatchedId: null,
        labelMatchedScore: 0,
        yearId: null,
        yearScore: 0,
      );
      expect(id, 'tt0970866');
    });
  });
}
