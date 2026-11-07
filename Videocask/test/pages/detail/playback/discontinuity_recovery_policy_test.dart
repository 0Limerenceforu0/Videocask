import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/playback/discontinuity_recovery_policy.dart';

/// 断网时 mpv 把读不到的流报成「提前播完」→ 触发纠偏 → 纠偏 seek 在死流上必然落空，
/// 形成无效循环（2026-10-21 模拟器实测）。策略必须连续失败达上限后彻底放弃。
void main() {
  test('前几次失败不放弃纠偏', () {
    final policy = DiscontinuityRecoveryPolicy(maxAttempts: 3);

    expect(policy.recordFailure(), isFalse);
    expect(policy.recordFailure(), isFalse);
    expect(policy.disabled, isFalse);
    expect(policy.failures, 2);
  });

  test('连续失败达上限后放弃纠偏', () {
    final policy = DiscontinuityRecoveryPolicy(maxAttempts: 3);

    expect(policy.recordFailure(), isFalse);
    expect(policy.recordFailure(), isFalse);
    expect(policy.recordFailure(), isTrue);
    expect(policy.disabled, isTrue);
  });

  test('放弃后继续记失败仍返回已放弃（不再触发纠偏）', () {
    final policy = DiscontinuityRecoveryPolicy(maxAttempts: 1);

    expect(policy.recordFailure(), isTrue);
    expect(policy.recordFailure(), isTrue);
    expect(policy.disabled, isTrue);
  });

  test('落位成功后清零失败计数', () {
    final policy = DiscontinuityRecoveryPolicy(maxAttempts: 3);
    policy.recordFailure();
    policy.recordFailure();

    policy.recordSuccess();

    expect(policy.failures, 0);
    expect(policy.disabled, isFalse);
  });

  test('换 open 代次自动复位（换集后值得重新尝试纠偏）', () {
    final policy = DiscontinuityRecoveryPolicy(maxAttempts: 2);
    policy.recordFailure();
    policy.recordFailure();
    expect(policy.disabled, isTrue);

    final changed = policy.syncGeneration(7);

    expect(changed, isTrue);
    expect(policy.disabled, isFalse);
    expect(policy.failures, 0);
  });

  test('同一 open 代次不重复复位', () {
    final policy = DiscontinuityRecoveryPolicy(maxAttempts: 2);
    policy.recordFailure();

    final changed = policy.syncGeneration(policy.generation);

    expect(changed, isFalse);
    expect(policy.failures, 1);
  });
}