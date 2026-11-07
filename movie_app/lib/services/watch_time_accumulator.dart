/// 累计观看时长的增量计算（纯函数，供单测）。
///
/// 历史记录每 5 秒保存一次，播放位置 [progressMs] 单调推进；但用户拖动进度条
/// 时位置会一次性跨越几分钟。若直接按 `progress - 上次进度` 累加，看一部片就
/// 会凭空空出几个小时——这正是旧统计页「时长」数字失真的根源。
///
/// 因此只接受 **正常播放推进** 的增量：
/// - 同一集同一线路：增量必须在 (0, [kMaxCountedAdvanceMs]] 之间；
/// - 换集 / 新记录：只计入当前集已播部分（同样受上限约束），
///   续播到中段时不会把前面没看的时长算进来。
///
/// 单次保存周期是 5 秒，3 倍速也只有 15 秒，30 秒上限足够容纳卡顿后的补报，
/// 又能挡住任何手动的进度跳跃。
const int kMaxCountedAdvanceMs = 30000;

/// 计算本次保存应计入的观看毫秒数。
///
/// [previousProgressMs] 为上次已保存的进度（新记录传 null）。
/// [sameEpisode] 表示本次与上次是否同一集同一线路。
int countWatchedAdvanceMs({
  required int progressMs,
  required bool sameEpisode,
  int? previousProgressMs,
}) {
  if (progressMs <= 0) return 0;
  if (!sameEpisode || previousProgressMs == null) {
    // 新集 / 新记录：从 0 播到 progressMs 的部分算看过，但最多只认一个保存
    // 周期（续播到中段时不会把前面没看的时长算进来）。
    return progressMs < kMaxCountedAdvanceMs ? progressMs : kMaxCountedAdvanceMs;
  }
  final delta = progressMs - previousProgressMs;
  if (delta <= 0) return 0;
  if (delta > kMaxCountedAdvanceMs) return 0;
  return delta;
}
