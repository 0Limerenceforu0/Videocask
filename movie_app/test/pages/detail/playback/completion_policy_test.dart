import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/completion_policy.dart';

void main() {
  group('resolvePrematureCompletion', () {
    test('第一次提前完成仍给一次恢复机会（分片截断还有救）', () {
      expect(
        resolvePrematureCompletion(recoveryAttempts: 0),
        CompletionAction.recover,
      );
    });

    test('恢复过后再报提前完成就结束本集，不再死循环', () {
      // 2026-11-05 实机：片源声明 3179s、真实只到 3113s，恢复目标本身就在
      // 流的尽头。旧实现每次都 recover，结果卡死 34 分钟没有下一集。
      expect(
        resolvePrematureCompletion(recoveryAttempts: 1),
        CompletionAction.finish,
      );
      expect(
        resolvePrematureCompletion(recoveryAttempts: 2),
        CompletionAction.finish,
      );
    });

    test('上限可配置，便于将来放宽重试次数', () {
      expect(
        resolvePrematureCompletion(recoveryAttempts: 1, maxAttempts: 3),
        CompletionAction.recover,
      );
      expect(
        resolvePrematureCompletion(recoveryAttempts: 3, maxAttempts: 3),
        CompletionAction.finish,
      );
    });
  });

  group('didPlayheadAdvance', () {
    const anchor = Duration(seconds: 3113);

    test('位置明显前进 → 恢复成功', () {
      expect(
        didPlayheadAdvance(
          anchor: anchor,
          current: anchor + const Duration(seconds: 3),
        ),
        isTrue,
      );
    });

    test('只前进 400ms → 视为没动（还在原地打转）', () {
      expect(
        didPlayheadAdvance(
          anchor: anchor,
          current: anchor + const Duration(milliseconds: 400),
        ),
        isFalse,
      );
    });

    test('位置回退 → 视为没动', () {
      expect(
        didPlayheadAdvance(
          anchor: anchor,
          current: anchor - const Duration(seconds: 6),
        ),
        isFalse,
      );
    });

    test('恰好等于容差不算前进（边界保守）', () {
      expect(
        didPlayheadAdvance(
          anchor: anchor,
          current: anchor + kPrematureAdvanceTolerance,
        ),
        isFalse,
      );
    });
  });
}
