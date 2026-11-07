/// 用户主动 seek 的「落位」判定。
///
/// 背景（2026-11-07 用户反馈）：点进度条后立刻点暂停 → 黑屏、进度条消失、
/// 过一会恢复但位置全错。根因之一是 mpv 的 `seek` 命令**异步**：旧实现
/// `await playerService.seek()` 一返回就 `onSeekFinished()`，把 lifecycle 从
/// `seeking` 放回 `playing`，于是 seek 前的旧 position 上报被当成正常进度
/// ingest，`PlayheadAuthority` 判「回跳 >20s」→ 纠偏 / 采纳旧值 → 进度被拽回。
///
/// 修法：seek 发出后保持 `seeking`，直到收到「落在目标附近」的第一条上报
/// （或一个兜底超时）才结束；期间所有旧上报整条丢弃。
library;

/// 落位容差：mpv 精确 seek 后第一条上报可能与目标差关键帧级别的一小段。
const Duration kSeekLandingTolerance = Duration(seconds: 3);

/// 落位兜底超时：迟迟不落位也不能让 lifecycle 永久卡在 seeking。
const Duration kSeekLandingTimeout = Duration(milliseconds: 2500);

/// 在途 seek 期间对一条 mpv 位置上报的裁决。
enum SeekPositionVerdict {
  /// 没有在途 seek：按常规 ingest 流程处理。
  noPendingSeek,

  /// 这条上报落在目标附近：结束 seeking，并让这条上报继续走常规 ingest。
  landed,

  /// seek 前 / seek 途中的旧上报：整条丢弃，既不写权威进度也不触发纠偏。
  ignoreStale,
}

SeekPositionVerdict classifySeekPosition({
  required Duration? pendingTarget,
  required Duration reported,
  Duration tolerance = kSeekLandingTolerance,
}) {
  final target = pendingTarget;
  if (target == null) return SeekPositionVerdict.noPendingSeek;
  if ((reported - target).abs() <= tolerance) {
    return SeekPositionVerdict.landed;
  }
  return SeekPositionVerdict.ignoreStale;
}
