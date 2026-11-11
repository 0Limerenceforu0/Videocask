/// 磁力流 seek 之后「画面是否真的回来了」的判定。
///
/// 背景（2026-11-11 用户反馈）：磁力资源点进度条后，加载提示先消失，画面
/// 还要再等几秒才出来。真机日志（14:50:05 seek → 3046s）：
///
/// ```
/// 14:50:05.46  seek 发起（mpv seeking=yes, cache-duration=0）
/// 14:50:07.96  seek 落位结束 target=3046s   ← 恰好 2500ms 兜底超时
/// 14:50:10.43  位置才推进到 3046.42s        ← 4.9s 后画面才真的出来
/// ```
///
/// 根因是 UI 把「进度权威落位」当成了「画面就绪」。磁力是「按 mpv 请求逐块
/// 下载」的本地流，seek 到未下载片段时 mpv 的 seek 会阻塞 5~10 秒，而
/// `kSeekLandingTimeout` 只有 2.5 秒 —— 那个超时是给进度权威兜底的，不该
/// 拿来当「可以撤掉加载提示」的依据。磁力还特意关闭了 `cache-pause`，所以
/// media_kit 的 buffering 流全程是 false，也兜不了底。
///
/// 这里的判定只看**出画证据**：
/// * 播放位置真的越过了目标（时钟在走 = 帧在送显）；
/// * 或 mpv 已经结束 seek 且目标附近有可立即播放的缓存（差一次解码）；
/// * 暂停态时钟不会走，只认「mpv 结束 seek」这条。
library;

/// 位置越过目标多少才算「新位置已经在放」。
///
/// 取 400ms：mpv 精确 seek 后 `time-pos` 会先钉在目标上，真的出画后时钟
/// 才开始推进；给 400ms 余量避免把「seek 命令落地」误当「帧已送显」。
const Duration kMagnetSeekVisibleAdvance = Duration(milliseconds: 400);

/// 「位置越过目标」的有效窗口上界。
///
/// mpv 刚收到 seek 命令时，个别情况下 `time-pos` 还报着 seek 之前的位置；
/// 反向 seek（从 1000s 拖到 100s）时，旧值 1000s 满足「越过目标」会立刻
/// 误判出画。因此只认落在 `[target+400ms, target+10s]` 里的上报 —— 真的
/// 在放时每 250ms 都会有一条，绝不会跨过这个窗口。
const Duration kMagnetSeekForwardWindow = Duration(seconds: 10);

/// mpv `demuxer-cache-duration` 门槛：超过它说明目标附近的数据已经到位。
const Duration kMagnetSeekPlayableCache = Duration(milliseconds: 200);

/// 暂停态宽限：mpv 结束 seek 后稍等一拍再撤，避免和帧上屏打架。
const Duration kMagnetSeekPausedGrace = Duration(milliseconds: 1500);

/// 最小展示时长：seek 落在已缓冲区域时几十毫秒就出画，避免加载提示闪一下。
const Duration kMagnetSeekVisualMinShow = Duration(milliseconds: 300);

/// 「缓冲很久」的提示时刻：到点不撤加载态，只把文案升级成超时说明。
///
/// 取 45s：2026-11-11 真机实测，2.2GB / 12 peer 的磁力流 seek 到 79%（6893s）
/// 后 mpv 直到 **20.0s** 才 `seeking=no` + `cache-duration=4.1s`；反向 seek 到
/// 58%（4791s）撞上 0 peer 死区时 45s 仍未出画。
///
/// 🔴 这里曾经是「到点就撤加载提示」的硬上限，实测会复现用户最初反馈的
/// 「加载没了、画面还没出来」——加载提示消失必须由**出画证据**触发，超时只
/// 能把文案降级成「仍在尝试」，不能把提示整个拿掉。
const Duration kMagnetSeekVisualSoftTimeout = Duration(seconds: 45);

/// 进入「慢缓冲」提示的时刻：超过它加载浮层额外提示仍在等画面，
/// 避免用户把长时间转圈当成卡死。
const Duration kMagnetSeekVisualSlowHint = Duration(seconds: 15);

/// 轮询间隔（读 mpv 属性，250ms 足够，不跟播放器心跳抢资源）。
const Duration kMagnetSeekVisualPollInterval = Duration(milliseconds: 250);

/// 单次属性读取的超时：磁力流下 mpv 可能正卡在 demuxer 读上，属性读会
/// 长时间不返回；超时后按「无证据」处理，不让轮询自己挂死。
const Duration kMagnetSeekPropertyTimeout = Duration(milliseconds: 800);

/// 是否结束「等磁力 seek 出画」的加载态。
///
/// [mpvSeeking] / [cacheDuration] 读不到（null）时按「无证据」处理，只靠
/// 位置推进收尾 —— 不会因为一次属性读失败就提前撤掉加载提示。
///
/// 🔴 这里**没有**「等够 N 秒就撤」的分支：加了就能复现用户报的 bug（加载
/// 提示先没、画面几秒后才出来）。长时间没出画由 UI 把文案升级成超时说明，
/// 真正的结束只有三种：出画证据、播放错误、页面/换集重置。
bool shouldFinishMagnetSeekVisualWait({
  required Duration target,
  required Duration reportedPosition,
  required bool? mpvSeeking,
  required Duration? cacheDuration,
  required bool playing,
  required Duration elapsed,
}) {
  if (elapsed < kMagnetSeekVisualMinShow) return false;
  final advancedPastTarget = reportedPosition >= target + kMagnetSeekVisibleAdvance;
  final withinForwardWindow =
      reportedPosition <= target + kMagnetSeekForwardWindow;
  if (advancedPastTarget && withinForwardWindow) return true;
  final cache = cacheDuration;
  if (mpvSeeking == false &&
      cache != null &&
      cache >= kMagnetSeekPlayableCache) {
    return true;
  }
  // 暂停态时播放时钟不会推进，`seeking=no` 就代表目标位置那一帧已解出。
  if (!playing && mpvSeeking == false && elapsed >= kMagnetSeekPausedGrace) {
    return true;
  }
  return false;
}

/// mpv 秒数属性文本 → 时长；读不到 / 非数字 / 负数返回 null。
Duration? parseMpvSeconds(String? raw) {
  if (raw == null) return null;
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite || value < 0) return null;
  return Duration(microseconds: (value * 1000000).round());
}

/// mpv 布尔属性文本（`yes` / `no`）→ bool；其它返回 null。
bool? parseMpvFlag(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == 'yes' || value == 'true') return true;
  if (value == 'no' || value == 'false') return false;
  return null;
}
