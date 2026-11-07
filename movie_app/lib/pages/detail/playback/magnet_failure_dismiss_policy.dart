/// 磁力失败态的「自动撤销」规则（纯函数，可单测）。
///
/// 背景（2026-11-07 用户反馈）：画面已经正常播放了，中间却还挂着
/// 「磁力播放失败 / 节点连上了，但一直没有数据下发」的卡片。
///
/// 成因有两层：
/// 1. 首帧看门狗（[MagnetFirstFramePolicy]）在 25s+8s / 40s 的窗口上判失败，
///    而慢种子常常在窗口边上才刚开始出画面 —— 这次判定就成了误报；
/// 2. 失败态一旦写进 `playbackErrorType`，**没有任何地方会撤销它**：
///    只有重新打开片源（`resetSession`）或用户手动点重试才会清掉。
///    于是卡片会一直压在一个明明在播的视频上。
///
/// 这里给第 2 层兜底：只要在失败态下**位置真的在连续往前推**，
/// 就说明播放是活的，失败结论作废。
///
/// 为什么按「连续推进」累计而不是看绝对位置：
/// * 用户拖动进度条会一次性跳几十分钟，那是 seek 不是播放；
/// * 缓存里反复上报同一个位置（delta = 0）说明画面是死的。
/// 两种都不能算「在播」，所以出现就清零重来。
abstract final class MagnetFailureDismissPolicy {
  /// 判「真的在播」需要的连续推进量。
  ///
  /// 取 1s：位置回调本身是亚秒级的，1s 足够过滤掉「seek 落位后只推进一帧」
  /// 的假象，又不至于让误报卡片多挂十几秒。
  static const Duration confirmProgress = Duration(seconds: 1);

  /// 单次位置回调超过这个量就当作 seek 跳变（正常播放每次只涨几十~几百 ms）。
  static const Duration seekJumpThreshold = Duration(seconds: 3);

  /// 累计「连续推进量」。
  ///
  /// [previousPosition] / [currentPosition] 是相邻两次位置回调；
  /// [accumulated] 是上一次调用的返回值。
  ///
  /// 回退、原地不动、以及跳变（seek）都返回 [Duration.zero] 重新计数。
  static Duration accumulate({
    required Duration accumulated,
    required Duration previousPosition,
    required Duration currentPosition,
  }) {
    final delta = currentPosition - previousPosition;
    if (delta <= Duration.zero) return Duration.zero;
    if (delta > seekJumpThreshold) return Duration.zero;
    return accumulated + delta;
  }

  /// 是否已经到了可以撤销磁力失败态的程度。
  static bool shouldDismiss({
    required bool magnetFailed,
    required Duration accumulated,
  }) {
    if (!magnetFailed) return false;
    return accumulated >= confirmProgress;
  }
}
