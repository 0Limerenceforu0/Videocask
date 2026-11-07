/// 「提前完成」（`completed` 比 `duration` 早到）的处理策略。
///
/// 背景（2026-11-05 实机）：
/// 片源把广告段的 `EXTINF` 时长算进了总时长，但分片的 PTS 并不推进，于是
/// **声明时长比真实可播内容长 50~66 秒**。播放到真实末端时 mpv 报 `completed`，
/// 位置比 `duration - 45s` 还小，被 [PlayheadAuthority.isPrematureComplete]
/// 判成「提前完成」。
///
/// 旧实现无条件走 `_recoverFromDiscontinuity`，而恢复目标本身就在流的尽头：
/// mpv 直接进入 idle，之后的 seek 全部被丢弃 —— 画面定格、`playing=true` 不变、
/// 自动连播永不触发，实测连续 34 分钟（69 条心跳）无人恢复。
///
/// 策略：恢复只给一次机会，之后必须落到「本集结束」；恢复是否真的救回来，
/// 由 [didPlayheadAdvance] 在观察窗末尾验证。
library;

/// `completed` 事件的处理决定。
enum CompletionAction {
  /// 还有救：按当前进度重新 seek，并在观察窗末尾验证位置是否推进。
  recover,

  /// 本集真的结束：落 ended 状态，交给自动连播 / 重播。
  finish,
}

/// 提前完成的恢复上限。
///
/// 一次就够：第二次恢复的目标与第一次完全相同（同一位置、同一条流），
/// 只会把「定格」再延长一个观察窗。
const int kMaxPrematureRecoveryAttempts = 1;

/// 恢复 seek 之后的位置验证窗口。窗口内位置没往前走，就认定 seek 落在流的尽头。
const Duration kPrematureRecoveryVerifyWindow = Duration(seconds: 12);

/// 判定「位置是否真的往前走了」的容差。
const Duration kPrematureAdvanceTolerance = Duration(seconds: 1);

/// 提前完成时该恢复还是该结束。
CompletionAction resolvePrematureCompletion({
  required int recoveryAttempts,
  int maxAttempts = kMaxPrematureRecoveryAttempts,
}) {
  if (recoveryAttempts < maxAttempts) return CompletionAction.recover;
  return CompletionAction.finish;
}

/// 恢复 seek 是否真的生效：观察窗结束时位置必须明显离开锚点。
bool didPlayheadAdvance({
  required Duration anchor,
  required Duration current,
  Duration tolerance = kPrematureAdvanceTolerance,
}) {
  return current > anchor + tolerance;
}
